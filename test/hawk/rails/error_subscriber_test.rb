# frozen_string_literal: true

require "test_helper"
require "support/rails_capture"

class RailsErrorSubscriberTest < RailsCaptureTest
  def test_explicit_rails_report_bypasses_request_only_exclusions
    Rails.error.report(ActiveRecord::RecordNotFound.new("explicit"), handled: true, severity: :warning,
                                                                     context: { pin: "hidden", section: "checkout" })

    assert_equal 1, @collector.events.size
    payload = @collector.events.last.fetch("payload")
    assert_equal true, payload.dig("addons", "handled")
    assert_equal "warning", payload.dig("addons", "level")
    assert_equal "[FILTERED]", payload.dig("context", "pin")
  end

  def test_reinitialization_keeps_one_subscriber_and_uses_current_client
    initialize_hawk
    Rails.error.report(RuntimeError.new("once"))

    assert_equal 1, @collector.events.size
  end

  def test_explicit_report_and_escaping_boundary_report_once
    error = RuntimeError.new("reported then raised")
    assert_raises(RuntimeError) do
      Hawk.capture do
        Rails.error.report(error)
        raise error
      end
    end

    assert_equal 1, @collector.events.size
  end

  def test_explicit_in_request_reports_include_current_request_data_without_leaking_it
    app = Hawk::Rack.new(lambda do |env|
      env["action_dispatch.request.parameters"] = { "order_id" => "42", "pin" => "hidden" }
      Rails.error.report(RuntimeError.new("inside request"), handled: true)
      [200, {}, ["ok"]]
    end, integration: :rails)
    app.call(Rack::MockRequest.env_for("/reported"))
    request = @collector.events.last.dig("payload", "addons", "request")
    assert_equal "/reported", request.fetch("path")
    assert_equal "[FILTERED]", request.dig("params", "pin")
    Rails.error.report(RuntimeError.new("outside request"))
    refute @collector.events.last.fetch("payload").fetch("addons").key?("request")
  end
end
