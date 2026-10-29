# frozen_string_literal: true

module Hawk
  # Reports events for one project with independent delivery and execution scopes.
  #
  # Use {.build} to construct a client with the standard transport.
  # Capture methods isolate reporting failures from application control flow.
  #
  # @example Report to another project
  #   config = Hawk::Configuration.new
  #   config.token = ENV.fetch("OTHER_HAWK_TOKEN")
  #   client = Hawk::Client.build(config)
  #   client.capture_message("Import completed")
  #   client.close
  class Client
    # @return [Configuration] validated settings; configure before building the client
    attr_reader :configuration

    # @return [Diagnostics] delivery and filtering counters
    attr_reader :diagnostics

    # Builds a client with the standard HTTP transport and delivery queue.
    #
    # @param configuration [Configuration] settings to validate and retain
    # @return [Client]
    # @raise [ConfigurationError] if configuration is invalid
    def self.build(configuration)
      diagnostics = Diagnostics.new(configuration.diagnostic_callback, logger: configuration.diagnostic_logger)
      delivery = Delivery.new(configuration, transport: Transport.new(configuration), diagnostics: diagnostics)
      new(configuration, delivery: delivery, diagnostics: diagnostics)
    end

    # @api private
    def initialize(configuration, delivery:, diagnostics: nil)
      configuration.validate!
      configuration.release = Release.detect(configuration)
      @configuration = configuration
      @delivery = delivery
      @diagnostics = diagnostics || Diagnostics.new(configuration.diagnostic_callback,
                                                    logger: configuration.diagnostic_logger)
      @store = ScopeStore.new(configuration, SecureRandom.uuid)
      @closed = false
    end

    # @return [Scope] mutable scope for this client, thread, and fiber
    def current_scope
      @store.current
    end

    # @return [Boolean] whether the client is open and enabled for this environment
    def enabled?
      !@closed && @configuration.enabled?
    end

    # Merges values into the current scope, replacing matching top-level keys.
    #
    # Values are copied into bounded JSON data without calling custom serializers.
    #
    # @param context [Hash{String, Symbol => Object}] application context
    # @return [void]
    def set_context(context)
      current_scope.set_context(context)
    end

    # Replaces the current scope's user. A nil value clears the scoped user.
    #
    # @param user [Hash{String, Symbol => Object}, nil] user data; include an :id when available
    # @return [void]
    def set_user(user)
      current_scope.set_user(user)
    end

    # Runs a block with a copy of the current scope and restores its parent.
    #
    # Restoration also occurs when the block raises an exception.
    #
    # @yield [scope] temporary scope for this execution
    # @yieldparam scope [Scope]
    # @yieldreturn [Object] application result
    # @return [Object] the block's result
    # @example Attach temporary context
    #   client.with_scope do |scope|
    #     scope.set_context(order_id: "42")
    #     client.capture_message("Order accepted")
    #   end
    def with_scope
      previous = current_scope
      @store.replace(previous.copy)
      begin
        yield current_scope
      ensure
        @store.replace(previous)
      end
    end

    # @api private
    def using_scope(scope)
      previous = current_scope
      @store.replace(scope.copy)
      begin
        yield
      ensure
        @store.replace(previous)
      end
    end

    # @api private
    def with_boundary(kind:, metadata:, inherit: false)
      previous = current_scope
      @store.clear_escape unless previous.boundary
      scope = boundary_scope(previous, kind, metadata, inherit)
      @store.replace(scope)
      begin
        yield
      ensure
        @store.replace(previous)
      end
    end

    # Reports an exception with the current scope and per-event overrides.
    #
    # Manual calls can report the same exception more than once. Filtering,
    # sampling, disabled capture, or delivery rejection can discard the event.
    #
    # @param exception [Exception] exception to report
    # @param context [Hash{String, Symbol => Object}] values merged over scoped context
    # @param user [Hash{String, Symbol => Object}, nil] per-event user; nil uses scope or configuration
    # @param level [Symbol] severity attached to the event, normally :error
    # @return [String, nil] local capture ID, or nil when the event is not accepted
    # @note A capture ID does not confirm receipt by Hawk.
    def capture_exception(exception, context: {}, user: nil, level: :error)
      identifier = dispatch(exception: exception, context: context, user: user, level: level)
      current_scope.ledger.accept(exception, evict: !current_scope.boundary) if identifier
      identifier
    end

    # Reports a message with the current scope and per-event overrides.
    #
    # @param message [String] event title
    # @param context [Hash{String, Symbol => Object}] values merged over scoped context
    # @param user [Hash{String, Symbol => Object}, nil] per-event user; nil uses scope or configuration
    # @param level [Symbol] severity attached to the event, normally :info
    # @return [String, nil] local capture ID, or nil when the event is not accepted
    # @note A capture ID does not confirm receipt by Hawk.
    def capture_message(message, context: {}, user: nil, level: :info)
      dispatch(message: message, context: context, user: user, level: level)
    end

    # Adds a filtered, timestamped breadcrumb to the current scope.
    #
    # Retains the most recent 50 entries. Hook failures discard the entry.
    #
    # @param entry [Hash{String, Symbol => Object}] fields such as :message and :category
    # @return [void]
    def add_breadcrumb(entry)
      Breadcrumbs.add(self, entry)
    end

    # Reports exceptions escaping a block and raises the same exception again.
    #
    # Inherits the current scope. Automatic reporting excludes normal process
    # termination, including SystemExit, SignalException, and Interrupt.
    #
    # @yield application work to monitor
    # @yieldreturn [Object] application result
    # @return [Object] the block's result
    # @raise [Exception] any exception raised by the block, after reporting when eligible
    def capture(&)
      Boundary.run(self, kind: :capture, metadata: {}, inherit: true, &)
    end

    # @api private
    def report(exception, mechanism:, context: {}, level: :error, handled: false)
      return if normal_termination?(exception)
      return if mechanism == "request" && expected_request_error?(exception)

      case current_scope.ledger.accept(exception, evict: !current_scope.boundary)
      when :duplicate then return nil
      when :overflow
        @diagnostics.increment(:duplicate_overflow)
        return nil
      end
      dispatch(exception: exception, context: context, level: level,
               addons: { "mechanism" => mechanism, "handled" => handled })
    end

    # @api private
    def remember_escape(exception)
      @store.remember_escape(exception)
    end

    # @api private
    def consume_escape(exception)
      @store.consume_escape(exception)
    end

    # Waits for pending attempts, including attempts that fail.
    #
    # @param timeout [Numeric] deadline in seconds
    # @return [Boolean] true if pending attempts finished; false on timeout or failure
    # @note Success does not confirm receipt by Hawk.
    def flush(timeout: @configuration.flush_timeout)
      @delivery.flush(timeout: timeout)
    rescue StandardError
      false
    end

    # Stops accepting events, clears this execution's scope, and drains delivery.
    #
    # @param timeout [Numeric] deadline in seconds
    # @return [Boolean] true if shutdown finished; false on timeout or failure
    # @note The client remains closed if shutdown times out.
    def close(timeout: @configuration.flush_timeout)
      @closed = true
      @store.clear
      @delivery.close(timeout: timeout)
    rescue StandardError
      false
    end

    private

    def boundary_scope(previous, kind, metadata, inherit)
      scope = inherit ? previous.copy : Scope.new(context: @configuration.context, user: @configuration.user)
      scope.ledger = previous.boundary ? previous.ledger : Scope::Ledger.new
      scope.boundary = true
      scope.addons = (inherit ? previous.addons : scope.addons).merge(metadata).merge("boundary" => kind.to_s)
      scope
    end

    def dispatch(exception: nil, message: nil, context: {}, user: nil, level: :error, addons: {})
      return unless eligible?(exception)

      identifier = SecureRandom.uuid
      encoded = Event.new(configuration: @configuration, id: identifier, exception: exception, message: message,
                          level: level, **current_scope.event_data(context, user, @configuration.user, addons)).encode
      unless encoded
        @diagnostics.increment(:filtered)
        return nil
      end
      identifier if @delivery.enqueue(identifier, encoded.freeze)
    rescue StandardError
      @diagnostics.increment(:failed)
      nil
    end

    def eligible?(exception)
      return false unless enabled?
      return false unless rand < @configuration.sample_rate
      return true unless exception

      names = exception.class.ancestors.filter_map(&:name)
      @configuration.ignored_exceptions.none? { |name| names.include?(name) }
    end

    def normal_termination?(exception)
      case exception
      when SystemExit, SignalException then true
      else false
      end
    end

    def expected_request_error?(exception)
      expected = %w[ActionController::RoutingError AbstractController::ActionNotFound
                    ActionController::UnknownAction ActiveRecord::RecordNotFound]
      exception.class.ancestors.any? { |ancestor| expected.include?(ancestor.name) }
    end
  end
end
