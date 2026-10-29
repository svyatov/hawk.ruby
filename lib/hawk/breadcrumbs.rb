# frozen_string_literal: true

module Hawk
  # Breadcrumb buffers belong to scopes; instrumentation guards belong to fibers.
  module Breadcrumbs
    def self.install(configuration)
      if configuration.breadcrumbs_logger || configuration.logger_error_level
        require_relative "breadcrumbs/logger"
        Logger.install
      end
      return unless configuration.breadcrumbs_http

      require_relative "breadcrumbs/net_http"
      NetHTTP.install
    end

    def self.guard(category)
      key = "hawk.instrumentation.#{category}"
      # @type var previous: top
      previous = Thread.current[key]
      Thread.current[key] = true
      yield
    ensure
      Thread.current[key] = previous
    end

    def self.suppressed?(category)
      # @type var value: top
      value = Thread.current["hawk.instrumentation.#{category}"]
      case value
      when true then true
      else false
      end
    end

    def self.client(category)
      client = Hawk.client
      return unless client&.enabled?
      return if suppressed?(:sdk) || suppressed?(category)

      client if enabled?(client.configuration, category)
    end

    def self.enabled?(config, category)
      case category
      when :logger then config.breadcrumbs_logger || !config.logger_error_level.nil?
      when :http then config.breadcrumbs_http
      when :rails then config.breadcrumbs_rails
      else false
      end
    end

    def self.add(client, raw)
      return unless client.enabled?

      entry = filtered(client.configuration, raw)
      return unless entry

      buffer = client.current_scope.breadcrumbs
      buffer << entry
      buffer.shift while buffer.size > 50
      nil
    rescue StandardError
      client.diagnostics.increment(:filtered)
      nil
    end

    def self.filtered(configuration, raw)
      entry = JSONValue.object(raw).merge("timestamp" => (Time.now.to_f * 1000).to_i)
      entry = JSONValue.object(Filter.new(configuration).call(entry))
      entry = framework_filtered(configuration, entry)
      return unless entry

      hook = configuration.before_breadcrumb
      return entry unless hook

      case result = Hook.call { hook.call(entry) }
      when Hash then JSONValue.object(result)
      end
    end

    def self.framework_filtered(configuration, entry)
      filter = configuration.framework_filter
      return entry unless filter

      case result = Hook.call { filter.call(entry) }
      when Hash then JSONValue.object(result)
      end
    end
    private_class_method :filtered, :enabled?, :framework_filtered
  end
end
