# frozen_string_literal: true

require "test_helper"
require "support/collector"
require "logger"
require "stringio"

class BreadcrumbFailuresTest < HawkTest
  class BrokenClient < Hawk::Client
    def add_breadcrumb(_entry)
      raise "breadcrumb storage failed"
    end
  end

  def setup
    @config = configuration
    @config.breadcrumbs_http = @config.breadcrumbs_logger = true
    @client = Hawk::Client.new(@config, delivery: RecordingDelivery.new)
    Hawk.instance_variable_set(:@client, @client)
    Hawk::Breadcrumbs.install(@config)
    @collector = Collector.new
  end

  def teardown
    Hawk.close
    @collector.close
  end

  def test_explicit_logger_objects_and_progname_are_observed_without_conversion_side_effects
    logger = Logger.new(StringIO.new)
    assert logger.add(Logger::INFO, { "event" => true })

    assert_equal "{\"event\":true}", @client.current_scope.breadcrumbs.last["message"]
    assert_nil Hawk::Breadcrumbs.client(:unknown)
  end

  def test_absolute_http_targets_strip_credentials_and_query_values
    uri = URI(@collector.url)
    http = Net::HTTP.new(uri.host, uri.port, nil)
    request = Net::HTTP::Post.new("#{@collector.url}/safe?password=hidden")
    assert_equal "200", http.request(request, "{}").code

    assert_equal "/safe", @client.current_scope.breadcrumbs.last.dig("data", "path")
  end

  def test_user_response_block_failure_is_not_reported_as_a_connection_failure
    uri = URI(@collector.url)
    error = RuntimeError.new("user response handler")
    observed = assert_raises(RuntimeError) do
      Net::HTTP.start(uri.host, uri.port) do |http|
        http.post("/", "{}")
        raise error
      end
    end

    assert_same error, observed
    assert_equal 1, @client.current_scope.breadcrumbs.size
  end

  def test_read_failure_retains_original_http_error_and_records_one_attempt
    @collector.delay = 0.1
    uri = URI(@collector.url)
    http = Net::HTTP.new(uri.host, uri.port, nil)
    http.read_timeout = 0.01
    assert_raises(Net::ReadTimeout) { http.post("/read", "{}") }

    assert_equal 1, @client.current_scope.breadcrumbs.size
    assert_nil @client.current_scope.breadcrumbs.last.dig("data", "status")
  end

  def test_sdk_storage_failures_do_not_replace_logger_or_http_results
    Hawk.instance_variable_set(:@client, BrokenClient.new(@config, delivery: RecordingDelivery.new))
    assert Logger.new(StringIO.new).info("storage failure")
    assert_equal "200", Net::HTTP.post(URI(@collector.url), "{}").code
    port = TCPServer.open("127.0.0.1", 0) { |server| server.addr[1] }

    assert_raises(Errno::ECONNREFUSED) { Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/")) }
  end
end
