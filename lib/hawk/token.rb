# frozen_string_literal: true

require "base64"
require "json"
require "uri"

module Hawk
  class ConfigurationError < ArgumentError; end

  # Resolves collector identity without exposing the integration secret.
  class Token
    LABEL = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i

    def self.decode(value)
      raise ConfigurationError, "Invalid Hawk integration token" if value.bytesize > 8192

      # @type var data: top
      data = JSON.parse(Base64.strict_decode64(value))
      id = integration_id(data)
      raise ConfigurationError, "Invalid Hawk integration token" unless id

      new(id)
    rescue JSON::ParserError, ArgumentError
      raise ConfigurationError, "Invalid Hawk integration token"
    end

    def self.integration_id(data)
      case data
      when Hash
        id = data["integrationId"]
        case id
        when String
          id if LABEL.match?(id) && valid_secret?(data["secret"])
        end
      end
    end

    def self.valid_secret?(value)
      case value
      when String then !value.empty?
      else false
      end
    end

    def initialize(integration_id)
      @integration_id = integration_id
    end

    def endpoint
      URI::HTTPS.build(host: "#{@integration_id}.k1.hawk.so")
    end
  end
end
