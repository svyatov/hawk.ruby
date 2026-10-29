# frozen_string_literal: true

require_relative "support/coverage_start"

require "minitest/autorun"
require "base64"
require "json"
require "hawk"

class HawkTest < Minitest::Test
  class RecordingDelivery
    attr_reader :payloads
    attr_accessor :accept, :failure

    def initialize
      @payloads = []
      @accept = true
      @failure = nil
    end

    def enqueue(_id, encoded)
      raise @failure if @failure
      return false unless @accept

      @payloads << JSON.parse(encoded).fetch("payload")
      true
    end

    def flush(timeout:)
      timeout >= 0
    end

    def close(timeout:)
      flush(timeout: timeout)
    end
  end

  def integration_token(id: "project-123", secret: "secret-123")
    Base64.strict_encode64(JSON.generate("integrationId" => id, "secret" => secret))
  end

  def configuration
    config = Hawk::Configuration.new
    config.token = integration_token
    config
  end

  def capture_client(config = configuration)
    delivery = RecordingDelivery.new
    [Hawk::Client.new(config, delivery: delivery), delivery]
  end
end
