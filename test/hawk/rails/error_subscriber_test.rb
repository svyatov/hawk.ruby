# frozen_string_literal: true

require "test_helper"
require "support/rails_capture_test"

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
end
