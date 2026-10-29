# frozen_string_literal: true

require_relative "hawk/version"
require_relative "hawk/token"
require_relative "hawk/configuration"
require_relative "hawk/release"
require_relative "hawk/json_value"
require_relative "hawk/filter"
require_relative "hawk/hook"
require_relative "hawk/filtered_fields"
require_relative "hawk/framework_filter"
require_relative "hawk/source"
require_relative "hawk/event"
require_relative "hawk/diagnostics"
require_relative "hawk/scope"
require_relative "hawk/scope_store"
require_relative "hawk/client"
require_relative "hawk/breadcrumbs"
require_relative "hawk/job_context"
require_relative "hawk/boundary"
require_relative "hawk/transport"
require_relative "hawk/delivery"
require_relative "hawk/process_hooks"

# Error reporting through a process-wide default {Client}.
#
# Initialize before starting application workers. Scope data belongs to the
# current thread and fiber. Capture IDs confirm local acceptance, not delivery.
#
# @example Configure and report
#   Hawk.init { |config| config.token = ENV.fetch("HAWK_TOKEN") }
#   Hawk.capture_message("Checkout completed", context: { order_id: "42" })
#   Hawk.flush(timeout: 5.0)
# @see Client For independent project clients.
module Hawk
  class << self
    # @return [Client, nil] default client, or nil before initialization or after close
    attr_reader :client

    # Configures and replaces the default client, closing the previous client.
    #
    # A missing or empty token disables capture. Loaded Rails integrations can
    # adjust configuration before validation. Initialize before concurrent use.
    #
    # @yield [configuration] configuration to customize
    # @yieldparam configuration [Configuration]
    # @return [Client] replacement client
    # @raise [ConfigurationError] if configuration is invalid
    def init
      configuration = Configuration.new
      yield configuration
      Rails.configure(configuration) if defined?(Hawk::Rails)
      replacement = Client.build(configuration)
      @client&.close
      @client = replacement
      Breadcrumbs.install(configuration)
      ProcessHooks.install if configuration.enabled? && configuration.global_errors
      replacement
    end

    # (see Client#capture_exception)
    # @note Returns nil when no default client exists.
    def capture_exception(exception, context: {}, user: nil, level: :error)
      @client&.capture_exception(exception, context: context, user: user, level: level)
    end

    # (see Client#capture_message)
    # @note Returns nil when no default client exists.
    def capture_message(message, context: {}, user: nil, level: :info)
      @client&.capture_message(message, context: context, user: user, level: level)
    end

    # (see Client#set_context)
    # @note Has no effect when no default client exists.
    def set_context(context)
      @client&.set_context(context)
    end

    # (see Client#add_breadcrumb)
    # @note Has no effect when no default client exists.
    def add_breadcrumb(entry)
      @client&.add_breadcrumb(entry)
    end

    # (see Client#set_user)
    # @note Has no effect when no default client exists.
    def set_user(user)
      @client&.set_user(user)
    end

    # (see Client#with_scope)
    # @note Without a default client, yields a temporary scope without storing it.
    def with_scope(&)
      client = @client
      client ? client.with_scope(&) : yield(Scope.new)
    end

    # (see Client#capture)
    # @note Without a default client, runs the block without reporting.
    def capture(&)
      client = @client
      client ? client.capture(&) : yield
    end

    # Waits for pending delivery attempts on the default client.
    #
    # @param timeout [Numeric, nil] deadline in seconds; nil uses Configuration#flush_timeout
    # @return [Boolean] true if attempts finished or no client exists;
    #   false on timeout or failure
    # @note Success does not confirm receipt by Hawk.
    def flush(timeout: nil)
      client = @client
      client ? client.flush(timeout: timeout || client.configuration.flush_timeout) : true
    end

    # Removes the default client and stops its delivery worker.
    #
    # @param timeout [Numeric, nil] deadline in seconds; nil uses Configuration#flush_timeout
    # @return [Boolean] true if shutdown finished or no client exists;
    #   false on timeout or failure
    # @note The default client is removed even when shutdown times out.
    def close(timeout: nil)
      previous = @client
      @client = nil
      previous ? previous.close(timeout: timeout || previous.configuration.flush_timeout) : true
    end
  end
end

require_relative "hawk/rails/integration" if defined?(Rails::Railtie)
