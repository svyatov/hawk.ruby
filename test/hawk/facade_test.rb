# frozen_string_literal: true

require "test_helper"
require "support/collector"

class FacadeTest < HawkTest
  def teardown
    Hawk.close
  end

  def test_initialization_sends_a_real_message_to_the_collector
    collector = Collector.new
    Hawk.init do |config|
      config.token = integration_token
      config.endpoint = collector.url
      config.delivery_mode = :sync
      config.global_errors = false
    end
    Hawk.set_context(section: "checkout")

    assert_kind_of String, Hawk.capture_message("message")
    assert_equal "checkout", collector.events.last.dig("payload", "context", "section")
    assert Hawk.flush(timeout: 0.1)
  ensure
    collector&.close
  end

  def test_uninitialized_capture_is_disabled_and_scoped_block_still_runs
    Hawk.close

    assert_nil Hawk.capture_message("disabled")
    assert_equal(7, Hawk.with_scope { 7 })
    assert_equal(8, Hawk.capture { 8 })
  end
end
