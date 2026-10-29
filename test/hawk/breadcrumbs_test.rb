# frozen_string_literal: true

require "test_helper"
require "logger"
require "stringio"
require "support/collector"

class BreadcrumbsTest < HawkTest
  def setup
    @client, @delivery = capture_client
  end

  def teardown
    Hawk.close
  end

  def test_breadcrumbs_are_bounded_and_filtered_before_storage
    seen = nil
    @client.configuration.before_breadcrumb = lambda do |entry|
      seen = entry
      entry
    end
    51.times { |index| @client.add_breadcrumb(message: "event-#{index}", data: { password: "hidden" }) }
    entries = @client.current_scope.breadcrumbs

    assert_equal 50, entries.size
    assert_equal "event-1", entries.first.fetch("message")
    assert_equal "[FILTERED]", entries.last.dig("data", "password")
    assert_equal "[FILTERED]", seen.dig("data", "password")
    assert_kind_of Integer, entries.last.fetch("timestamp")
  end

  def test_hook_failures_and_invalid_results_drop_only_that_breadcrumb
    [->(_) { raise "hook failed" }, ->(_) { false }, ->(_) { "invalid" }].each do |hook|
      @client.configuration.before_breadcrumb = hook
      @client.add_breadcrumb(message: "dropped")
    end

    assert_empty @client.current_scope.breadcrumbs
    assert @client.capture_message("still accepts events")
  end

  def test_scopes_do_not_share_breadcrumb_buffers
    @client.add_breadcrumb(message: "parent")
    @client.with_scope { @client.add_breadcrumb(message: "child") }

    assert_equal(["parent"], @client.current_scope.breadcrumbs.map { |entry| entry.fetch("message") })
  end

  def initialize_default(**settings)
    Hawk.init do |config|
      config.token = integration_token
      config.global_errors = false
      config.sample_rate = 0
      settings.each { |key, value| config.public_send("#{key}=", value) }
    end
  end

  def test_logger_evaluates_blocks_once_and_retains_return_value
    initialize_default(breadcrumbs_logger: true)
    output = StringIO.new
    logger = Logger.new(output)
    calls = 0
    result = logger.info do
      calls += 1
      "once"
    end
    logger.level = Logger::ERROR
    logger.info { raise "filtered block must not run" }

    assert_equal true, result
    assert_equal 1, calls
    assert_includes output.string, "once"
    assert_equal(["once"], Hawk.client.current_scope.breadcrumbs.map { |entry| entry.fetch("message") })
  end

  def test_failed_logger_block_preserves_error_and_does_not_store_a_breadcrumb
    initialize_default(breadcrumbs_logger: true)
    error = RuntimeError.new("original block failure")
    logger = Logger.new(StringIO.new)

    assert_same error, assert_raises(RuntimeError) { logger.error { raise error } }
    assert_empty Hawk.client.current_scope.breadcrumbs
  end

  def test_http_records_one_entry_and_removes_query_values
    initialize_default(breadcrumbs_http: true)
    collector = Collector.new
    uri = URI("#{collector.url}/safe?password=#{SecureRandom.hex}")
    Net::HTTP.post(uri, "{}")
    entries = Hawk.client.current_scope.breadcrumbs

    assert_equal 1, entries.size
    assert_equal "/safe", entries.last.dig("data", "path")
    assert_equal "200", entries.last.dig("data", "status")
  ensure
    collector&.close
  end

  def test_failed_http_keeps_exception_and_records_operation
    initialize_default(breadcrumbs_http: true)
    port = TCPServer.open("127.0.0.1", 0) { |server| server.addr[1] }
    assert_raises(Errno::ECONNREFUSED) { Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/failed")) }

    entry = Hawk.client.current_scope.breadcrumbs.last
    assert_equal "CONNECT", entry.dig("data", "method")
    assert_equal "127.0.0.1", entry.dig("data", "host")
  end

  def test_transport_and_diagnostic_logs_are_excluded_from_instrumentation
    collector = Collector.new
    diagnostic_logger = Logger.new(StringIO.new)
    Hawk.init do |config|
      config.token = integration_token
      config.endpoint = collector.url
      config.delivery_mode = :sync
      config.global_errors = false
      config.breadcrumbs_logger = config.breadcrumbs_http = true
      config.diagnostic_logger = diagnostic_logger
    end
    Hawk.capture_message("event")

    assert_equal 1, collector.events.size
    assert_empty Hawk.client.current_scope.breadcrumbs
  ensure
    collector&.close
  end
end
