# frozen_string_literal: true

module Hawk
  # Settings are validated before clients install handlers or start delivery.
  class Configuration
    attr_accessor :token, :endpoint, :environment, :enabled_environments, :release, :detect_release,
                  :sample_rate, :delivery_mode, :queue_capacity, :source_roots, :send_source,
                  :connect_timeout, :read_timeout, :write_timeout, :flush_timeout, :limit_cooldown,
                  :context, :user, :ignored_exceptions, :filter_parameters, :integrations, :global_errors,
                  :before_send, :before_breadcrumb, :framework_filter, :diagnostic_callback, :diagnostic_logger,
                  :propagate_job_context,
                  :include_request_body, :include_job_arguments, :include_headers, :include_cookies,
                  :breadcrumbs_logger, :breadcrumbs_http, :breadcrumbs_rails, :logger_error_level

    def initialize
      initialize_identity
      initialize_delivery
      initialize_privacy
      initialize_hooks
    end

    def validate!
      value = @token
      Token.decode(value) if value && !value.empty?
      collector_uri if enabled?
      validate_delivery
      validate_callbacks
      unless valid_number?(@sample_rate) && @sample_rate <= 1
        raise ConfigurationError, "sample_rate must be finite and between 0 and 1"
      end

      nil
    end

    def enabled?
      value = @token
      environments = @enabled_environments
      !!(value && !value.empty? && (environments.nil? || environments.include?(@environment)))
    end

    def collector_uri
      override = @endpoint
      return Token.decode(@token || "").endpoint unless override

      uri = URI.parse(override)
      raise ConfigurationError, "Collector endpoint must use HTTPS or loopback HTTP" unless allowed_uri?(uri)

      uri
    rescue URI::InvalidURIError
      raise ConfigurationError, "Invalid collector endpoint"
    end

    def integration_enabled?(name)
      @integrations.fetch(name, true)
    end

    private

    def allowed_uri?(uri)
      return false unless uri.host && uri.userinfo.nil? && uri.fragment.nil?
      return true if uri.is_a?(URI::HTTPS)

      uri.is_a?(URI::HTTP) && ["127.0.0.1", "::1"].include?(uri.hostname)
    end

    def initialize_identity
      @token = ENV.fetch("HAWK_TOKEN", nil)
      @endpoint = nil
      @environment = ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
      @enabled_environments = nil
      @release = ENV["HAWK_RELEASE"] || ENV.fetch("REVISION", nil)
      @detect_release = false
      @source_roots = [Dir.pwd]
      @send_source = true
    end

    def initialize_delivery
      @sample_rate = 1.0
      @delivery_mode = :async
      @queue_capacity = 100
      @connect_timeout = 1.0
      @read_timeout = 2.0
      @write_timeout = 2.0
      @flush_timeout = 5.0
      @limit_cooldown = 60.0
    end

    def initialize_privacy
      @context = {}
      @user = nil
      @ignored_exceptions = []
      @filter_parameters = []
      @include_request_body = false
      @include_job_arguments = false
      @include_headers = false
      @include_cookies = false
    end

    def initialize_hooks
      @before_send = nil
      @before_breadcrumb = nil
      @framework_filter = nil
      @diagnostic_callback = nil
      @diagnostic_logger = nil
      @propagate_job_context = true
      @integrations = {}
      @global_errors = true
      @breadcrumbs_logger = false
      @breadcrumbs_http = false
      @breadcrumbs_rails = true
      @logger_error_level = nil
    end

    def validate_delivery
      unless @queue_capacity.is_a?(Integer) && @queue_capacity.positive?
        raise ConfigurationError, "queue_capacity must be a positive integer"
      end
      raise ConfigurationError, "delivery_mode must be async or sync" unless %i[async sync].include?(@delivery_mode)

      [@connect_timeout, @read_timeout, @write_timeout, @flush_timeout, @limit_cooldown].each do |value|
        raise ConfigurationError, "Timeouts must be finite and nonnegative" unless valid_number?(value)
      end
    end

    def valid_number?(value)
      case value
      when Float, Integer then value.finite? && value >= 0
      else false
      end
    end

    def validate_callbacks
      [@before_send, @before_breadcrumb, @framework_filter, @diagnostic_callback].each do |callback|
        raise ConfigurationError, "Hooks must be callable" unless callback.nil? || callback.respond_to?(:call)
      end
    end
  end
end
