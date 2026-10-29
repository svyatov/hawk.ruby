# frozen_string_literal: true

require "test_helper"
require "support/collector"
require "logger"
require "stringio"

class LoggerEventsTest < HawkTest
  def setup
    @collector = Collector.new
    Hawk.init do |config|
      config.token = integration_token
      config.endpoint = @collector.url
      config.global_errors = false
      config.delivery_mode = :sync
      config.logger_error_level = Logger::ERROR
    end
  end

  def teardown
    Hawk.close
    @collector.close
  end

  def test_log_events_require_explicit_threshold_and_preserve_messages
    logger = Logger.new(StringIO.new)
    logger.warn("below threshold")
    logger.error("explicit event")

    assert_equal 1, @collector.events.size
    assert_equal "explicit event", @collector.events.last.dig("payload", "title")
    assert_empty Hawk.client.current_scope.breadcrumbs
  end
end
