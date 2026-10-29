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

# The default client offers the same capture API as independent project clients.
module Hawk
  class << self
    attr_reader :client

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

    def capture_exception(exception, context: {}, user: nil, level: :error)
      @client&.capture_exception(exception, context: context, user: user, level: level)
    end

    def capture_message(message, context: {}, user: nil, level: :info)
      @client&.capture_message(message, context: context, user: user, level: level)
    end

    def set_context(context)
      @client&.set_context(context)
    end

    def add_breadcrumb(entry)
      @client&.add_breadcrumb(entry)
    end

    def set_user(user)
      @client&.set_user(user)
    end

    def with_scope(&)
      client = @client
      client ? client.with_scope(&) : yield(Scope.new)
    end

    def capture(&)
      client = @client
      client ? client.capture(&) : yield
    end

    def flush(timeout: nil)
      client = @client
      client ? client.flush(timeout: timeout || client.configuration.flush_timeout) : true
    end

    def close(timeout: nil)
      previous = @client
      @client = nil
      previous ? previous.close(timeout: timeout || previous.configuration.flush_timeout) : true
    end
  end
end

require_relative "hawk/rails/integration" if defined?(Rails::Railtie)
