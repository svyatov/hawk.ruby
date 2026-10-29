# frozen_string_literal: true

module Hawk
  # Owns policy and scope state; delivery receives detached JSON strings.
  class Client
    attr_reader :configuration, :diagnostics

    def self.build(configuration)
      diagnostics = Diagnostics.new(configuration.diagnostic_callback)
      delivery = Delivery.new(configuration, transport: Transport.new(configuration), diagnostics: diagnostics)
      new(configuration, delivery: delivery, diagnostics: diagnostics)
    end

    def initialize(configuration, delivery:, diagnostics: nil)
      configuration.validate!
      configuration.release = Release.detect(configuration)
      @configuration = configuration
      @delivery = delivery
      @diagnostics = diagnostics || Diagnostics.new(configuration.diagnostic_callback)
      @store = ScopeStore.new(configuration, SecureRandom.uuid)
      @closed = false
    end

    def current_scope
      @store.current
    end

    def enabled?
      !@closed && @configuration.enabled?
    end

    def set_context(context)
      current_scope.set_context(context)
    end

    def set_user(user)
      current_scope.set_user(user)
    end

    def with_scope
      previous = current_scope
      @store.replace(previous.copy)
      yield current_scope
    ensure
      @store.replace(previous) if previous
    end

    def using_scope(scope)
      previous = current_scope
      @store.replace(scope.copy)
      yield
    ensure
      @store.replace(previous) if previous
    end

    def with_boundary(kind:, metadata:, inherit: false)
      previous = current_scope
      @store.clear_escape unless previous.boundary
      scope = boundary_scope(previous, kind, metadata, inherit)
      @store.replace(scope)
      yield
    ensure
      @store.replace(previous) if previous
    end

    def capture_exception(exception, context: {}, user: nil, level: :error)
      identifier = dispatch(exception: exception, context: context, user: user, level: level)
      current_scope.ledger.accept(exception) if identifier
      identifier
    end

    def capture_message(message, context: {}, user: nil, level: :info)
      dispatch(message: message, context: context, user: user, level: level)
    end

    def capture(&)
      Boundary.run(self, kind: :capture, metadata: {}, inherit: true, &)
    end

    def report(exception, mechanism:, context: {}, level: :error, handled: false)
      return if normal_termination?(exception)
      return if mechanism == "request" && expected_request_error?(exception)

      case current_scope.ledger.accept(exception)
      when :duplicate then return nil
      when :overflow
        @diagnostics.increment(:duplicate_overflow)
        return nil
      end
      dispatch(exception: exception, context: context, level: level,
               addons: { "mechanism" => mechanism, "handled" => handled })
    end

    def remember_escape(exception)
      @store.remember_escape(exception)
    end

    def consume_escape(exception)
      @store.consume_escape(exception)
    end

    def flush(timeout: @configuration.flush_timeout)
      @delivery.flush(timeout: timeout)
    rescue StandardError
      false
    end

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

      scope = current_scope
      identifier = SecureRandom.uuid
      encoded = Event.new(configuration: @configuration, id: identifier, exception: exception, message: message,
                          context: scope.context.merge(JSONValue.object(context)), user: event_user(user, scope),
                          level: level, breadcrumbs: scope.breadcrumbs, addons: scope.addons.merge(addons)).encode
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

    def event_user(user, scope)
      value = JSONValue.object(user || scope.user || @configuration.user || {})
      value["id"] ||= scope.anonymous_id
      value
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
