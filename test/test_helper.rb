# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  coverage :line
  coverage :branch
  cover "lib/**/*.rb"
end

require "minitest/autorun"
require "base64"
require "json"
require "hawk"

class HawkTest < Minitest::Test
  def integration_token(id: "project-123", secret: "secret-123")
    Base64.strict_encode64(JSON.generate("integrationId" => id, "secret" => secret))
  end

  def configuration
    config = Hawk::Configuration.new
    config.token = integration_token
    config
  end
end
