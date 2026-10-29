# frozen_string_literal: true

require "test_helper"
require "support/collector"
require "support/rails_app"

class RailsRequestTest < HawkTest
  def setup
    @collector = Collector.new
    Hawk.init do |config|
      config.token = integration_token
      config.endpoint = @collector.url
      config.delivery_mode = :sync
      config.global_errors = false
    end
    @request = Rack::MockRequest.new(HawkFixtureApp)
  end

  def teardown
    Hawk.close
    @collector.close
  end

  def test_successful_request_has_normal_response
    response = @request.get("/ok")

    assert_equal 200, response.status
    assert_equal "ok", response.body
    assert_empty @collector.events
  end

  def test_rails_rendered_error_is_reported_with_request_metadata
    secret = SecureRandom.hex
    response = @request.get("/boom?pin=1234&password=#{secret}")

    assert_equal 500, response.status
    assert_equal 1, @collector.events.size
    payload = @collector.events.last.fetch("payload")
    assert_equal "controller failed", payload.fetch("title")
    assert_equal "boom", payload.dig("addons", "request", "action")
    assert_equal "[FILTERED]", payload.dig("addons", "request", "params", "pin")
    refute_includes JSON.generate(payload), secret
  end

  def test_expected_missing_record_and_routing_errors_are_excluded
    assert_equal 404, @request.get("/missing").status
    assert_equal 404, @request.get("/no-route").status
    assert_empty @collector.events
  end

  def test_request_scope_is_restored_between_requests
    @request.get("/scoped")
    @request.get("/boom")

    assert_nil @collector.events.last.dig("payload", "context", "private_scope")
  end

  def test_rails_filter_runs_before_user_before_send_hook
    observed = nil
    Hawk.client.configuration.before_send = lambda do |payload|
      observed = payload
      payload
    end
    @request.get("/boom?pin=1234")

    assert_equal "[FILTERED]", observed.dig("addons", "request", "params", "pin")
  end
end
