# frozen_string_literal: true

require "test_helper"
require "logger"
require "stringio"

class ReviewRegressionsTest < HawkTest
  def teardown
    Hawk.close
  end

  def test_unbounded_execution_lifetime_retains_only_recent_duplicate_identities
    client, delivery = capture_client
    300.times { |index| client.report(RuntimeError.new("report #{index}"), mechanism: "standalone") }

    assert_equal 300, delivery.payloads.size
    error = RuntimeError.new("recent manual capture")
    client.capture_exception(error)
    assert_nil client.report(error, mechanism: "process")
    assert_equal 301, delivery.payloads.size
  end

  def test_an_owned_boundary_still_limits_unique_automatic_reports
    client, delivery = capture_client
    client.with_boundary(kind: :test, metadata: {}) do
      257.times { |index| client.report(RuntimeError.new("report #{index}"), mechanism: "test") }
    end

    assert_equal 256, delivery.payloads.size
    assert_equal 1, client.diagnostics.snapshot[:duplicate_overflow]
  end

  def test_logging_inside_hooks_is_not_automatically_instrumented
    output = StringIO.new
    logger = Logger.new(output)
    install_logging_hook(logger)
    assert logger.info("application log")

    assert_equal 1, @hook_calls
    assert_equal 2, output.string.lines.size
    assert_equal(["application log"], Hawk.client.current_scope.breadcrumbs.map { |entry| entry["message"] })
  end

  def test_logger_event_hooks_do_not_create_additional_events_or_evaluate_the_message_again
    output = StringIO.new
    logger = Logger.new(output)
    delivery = install_logging_hook(logger, error_events: true)
    evaluations = 0
    assert(logger.error do
      evaluations += 1
      "application error"
    end)

    assert_equal 1, evaluations
    assert_equal 2, @hook_calls
    assert_equal 3, output.string.lines.size
    assert_equal(["application error"], delivery.payloads.map { |event| event["title"] })
  end

  private

  def install_logging_hook(logger, error_events: false)
    @hook_calls = 0
    config = configuration
    config.breadcrumbs_logger = true
    hook = lambda do |entry|
      @hook_calls += 1
      logger.error("hook log") if @hook_calls < 4
      entry
    end
    config.before_breadcrumb = hook
    config.before_send = hook if error_events
    config.logger_error_level = Logger::ERROR if error_events
    client, delivery = capture_client(config)
    Hawk.instance_variable_set(:@client, client)
    Hawk::Breadcrumbs.install(config)
    delivery
  end
end
