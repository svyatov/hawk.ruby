# frozen_string_literal: true

module Hawk
  # Settings are validated before clients install handlers or start delivery.
  # Configure settings before calling {Hawk.init} or {Client.build}.
  # @see file:docs/configuration.md Configuration guide
  class Configuration
    # Project integration token. Defaults to ENV["HAWK_TOKEN"]; nil or empty disables capture.
    #
    # @return [String, nil]
    attr_accessor :token

    # Collector URL override. Defaults to the token-derived endpoint; permits HTTPS or loopback HTTP.
    #
    # @return [String, nil]
    attr_accessor :endpoint

    # Event environment. Defaults to RAILS_ENV, RACK_ENV, or "development", in that order.
    #
    # @return [String]
    attr_accessor :environment

    # Environments that permit capture. Defaults to nil, which permits all environments.
    #
    # @return [Array<String>, nil]
    attr_accessor :enabled_environments

    # Application revision. Defaults to HAWK_RELEASE or REVISION.
    #
    # @return [String, nil]
    attr_accessor :release

    # Detect the Git revision at initialization when release is unset. Defaults to false.
    #
    # @return [Boolean]
    attr_accessor :detect_release

    # Capture probability from 0.0 through 1.0. Defaults to 1.0.
    #
    # @return [Float]
    attr_accessor :sample_rate

    # Delivery policy: :async queues events; :sync sends in the caller. Defaults to :async.
    #
    # @return [Symbol]
    attr_accessor :delivery_mode

    # Maximum waiting events, as a positive integer. Defaults to 100.
    #
    # @return [Integer]
    attr_accessor :queue_capacity

    # Allowed roots for source snippets. Defaults to [Dir.pwd].
    #
    # @return [Array<String>]
    attr_accessor :source_roots

    # Include bounded source snippets from source_roots. Defaults to true.
    #
    # @return [Boolean]
    attr_accessor :send_source

    # Nonnegative connection timeout in seconds. Defaults to 1.0.
    #
    # @return [Numeric]
    attr_accessor :connect_timeout

    # Nonnegative socket read timeout in seconds. Defaults to 2.0.
    #
    # @return [Numeric]
    attr_accessor :read_timeout

    # Nonnegative socket write timeout in seconds. Defaults to 2.0.
    #
    # @return [Numeric]
    attr_accessor :write_timeout

    # Nonnegative flush and close deadline in seconds. Defaults to 5.0.
    #
    # @return [Numeric]
    attr_accessor :flush_timeout

    # Nonnegative fallback cooldown after collector limits, in seconds. Defaults to 60.0.
    #
    # @return [Numeric]
    attr_accessor :limit_cooldown

    # Initial context for execution scopes. Defaults to an empty hash.
    #
    # @return [Hash{String, Symbol => Object}]
    attr_accessor :context

    # Initial user data, preferably with an :id. Defaults to nil.
    #
    # @return [Hash{String, Symbol => Object}, nil]
    attr_accessor :user

    # Exception ancestor names excluded from capture. Defaults to an empty array.
    #
    # @return [Array<String>]
    attr_accessor :ignored_exceptions

    # Sensitive key patterns added to built-in filters. Defaults to an empty array.
    #
    # @return [Array<String, Regexp>]
    attr_accessor :filter_parameters

    # Integration switches. Unspecified integrations are enabled; defaults to an empty hash.
    #
    # @return [Hash{Symbol => Boolean}]
    attr_accessor :integrations

    # Install uncaught main-process exception capture and exit draining. Defaults to true.
    #
    # @return [Boolean]
    attr_accessor :global_errors

    # Receives a detached, filtered event hash without the token. Returns a hash to send or nil to
    # drop. Defaults to nil.
    #
    # @return [#call, nil]
    attr_accessor :before_send

    # Receives a detached, filtered breadcrumb hash. Returns a hash to retain or nil to drop.
    # Defaults to nil.
    #
    # @return [#call, nil]
    attr_accessor :before_breadcrumb

    # Framework filter receiving a payload hash and returning a hash or nil. Defaults to nil.
    #
    # @return [#call, nil]
    attr_accessor :framework_filter

    # Receives counter snapshots as `Hash{Symbol => Integer}`. Defaults to nil; return values are
    # ignored.
    #
    # @return [#call, nil]
    attr_accessor :diagnostic_callback

    # Receives sanitized warnings containing counters without event data. Defaults to nil.
    #
    # @return [#warn, nil]
    attr_accessor :diagnostic_logger

    # Propagate explicit context and user through supported job adapters. Defaults to true.
    #
    # @return [Boolean]
    attr_accessor :propagate_job_context

    # Include already available request bodies without reading the input stream. Defaults to false.
    #
    # @return [Boolean]
    attr_accessor :include_request_body

    # Include job arguments in captured metadata. Defaults to false.
    #
    # @return [Boolean]
    attr_accessor :include_job_arguments

    # Include request headers, excluding cookies. Defaults to false.
    #
    # @return [Boolean]
    attr_accessor :include_headers

    # Include request cookies in their dedicated field. Defaults to false.
    #
    # @return [Boolean]
    attr_accessor :include_cookies

    # Install automatic Logger breadcrumbs. Defaults to false.
    #
    # @return [Boolean]
    attr_accessor :breadcrumbs_logger

    # Install automatic Net::HTTP breadcrumbs. Defaults to false.
    #
    # @return [Boolean]
    attr_accessor :breadcrumbs_http

    # Enable Rails notification breadcrumbs when Rails is active. Defaults to true.
    #
    # @return [Boolean]
    attr_accessor :breadcrumbs_rails

    # Minimum Logger severity converted into events. Defaults to nil, which disables conversion.
    #
    # @return [Integer, nil]
    attr_accessor :logger_error_level

    # Creates settings with environment-derived identity and bounded delivery defaults.
    def initialize
      initialize_identity
      initialize_delivery
      initialize_privacy
      initialize_hooks
    end

    # Validates token, collector URL, delivery limits, sampling, and callable hooks.
    #
    # @return [nil]
    # @raise [ConfigurationError] if a checked setting is invalid
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

    # @return [Boolean] whether a nonempty token and the environment permit capture
    # @note This check does not validate the token.
    def enabled?
      value = @token
      environments = @enabled_environments
      !!(value && !value.empty? && (environments.nil? || environments.include?(@environment)))
    end

    # Resolves the configured collector URL or derives one from the token.
    #
    # @return [URI::HTTP, URI::HTTPS] collector URI
    # @raise [ConfigurationError] if the token or URL is invalid
    def collector_uri
      override = @endpoint
      return Token.decode(@token || "").endpoint unless override

      uri = URI.parse(override)
      raise ConfigurationError, "Collector endpoint must use HTTPS or loopback HTTP" unless allowed_uri?(uri)

      uri
    rescue URI::InvalidURIError
      raise ConfigurationError, "Invalid collector endpoint"
    end

    # @param name [Symbol] integration key, such as :rack or :sidekiq
    # @return [Boolean] configured switch, or true when unspecified
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
