# frozen_string_literal: true

require "test_helper"
require "rack/mock"
require "rack/lint"
require "stringio"
require "hawk/rack"

class RackIntegrationTest < HawkTest
  class FailingBody
    attr_reader :closed

    def initialize(error, close_error: nil)
      @error = error
      @close_error = close_error
      @closed = false
    end

    def each
      yield "part"
      raise @error
    end

    def close
      @closed = true
      raise @close_error if @close_error
    end
  end

  class CallableBody
    def call(stream)
      stream.write("part")
      raise "stream failed"
    end
  end

  def setup
    @delivery = RecordingDelivery.new
    @client = Hawk::Client.new(configuration, delivery: @delivery)
  end

  def test_response_is_valid_under_real_rack_lint
    app = Hawk::Rack.new(->(_env) { [200, { "content-type" => "text/plain" }, ["ok"]] }, client: @client)
    response = Rack::MockRequest.new(Rack::Lint.new(app)).get("/")

    assert_equal 200, response.status
    assert_equal "ok", response.body
    assert_empty @delivery.payloads
  end

  def test_escaping_application_error_is_reported_and_reraised
    error = RuntimeError.new("application failed")
    app = Hawk::Rack.new(->(_env) { raise error }, client: @client)

    assert_same error, assert_raises(RuntimeError) { app.call(Rack::MockRequest.env_for("/boom")) }
    assert_equal 1, @delivery.payloads.size
    assert_equal "/boom", @delivery.payloads.last.dig("addons", "request", "path")
  end

  def test_manual_reports_read_request_metadata_at_the_time_of_capture
    app = Hawk::Rack.new(lambda do |env|
      env["action_dispatch.request.parameters"] = { "order" => "42", "password" => "hidden" }
      @client.with_scope { @client.capture_message("inside request") }
      [200, {}, ["ok"]]
    end, client: @client)
    app.call(Rack::MockRequest.env_for("/manual", "REQUEST_METHOD" => "POST"))
    request = @delivery.payloads.last.dig("addons", "request")

    assert_equal "/manual", request&.fetch("path")
    assert_equal "POST", request.fetch("method")
    assert_equal({ "order" => "42", "password" => "[FILTERED]" }, request.fetch("params"))
  end

  def test_streamed_failure_keeps_request_scope_after_middleware_returns
    error = RuntimeError.new("stream failed")
    original = FailingBody.new(error)
    app = Hawk::Rack.new(->(_env) { [200, {}, original] }, client: @client)
    _status, _headers, body = app.call(Rack::MockRequest.env_for("/stream"))
    parts = []
    observed = assert_raises(RuntimeError) { body.each { |part| parts << part } }
    body.close

    assert_same error, observed
    assert_equal ["part"], parts
    assert original.closed
    assert_equal 1, @delivery.payloads.size
    assert_equal "/stream", @delivery.payloads.last.dig("addons", "request", "path")
  end

  def test_body_close_failure_is_reported
    failure = RuntimeError.new("close failed")
    body = FailingBody.new(RuntimeError.new("iteration"), close_error: failure)
    app = Hawk::Rack.new(->(_env) { [200, {}, body] }, client: @client)
    _status, _headers, wrapped = app.call(Rack::MockRequest.env_for("/close"))

    assert_same failure, assert_raises(RuntimeError) { wrapped.close }
    assert_equal "close failed", @delivery.payloads.last.fetch("title")
  end

  def test_callable_stream_preserves_writes_and_reports_failure
    app = Hawk::Rack.new(->(_env) { [200, {}, CallableBody.new] }, client: @client)
    _status, _headers, body = app.call(Rack::MockRequest.env_for("/callable"))
    stream = StringIO.new

    assert_raises(RuntimeError) { body.call(stream) }
    assert_equal "part", stream.string
    assert_equal "stream failed", @delivery.payloads.last.fetch("title")
  end

  def test_each_without_block_is_lazy_and_to_path_is_preserved_only_when_supported
    plain = Hawk::Rack.new(->(_) { [200, {}, ["part"]] }, client: @client)
    body = plain.call(Rack::MockRequest.env_for("/"))[2]

    assert_equal ["part"], body.each.to_a
    refute_respond_to body, :to_path
    File.open(__FILE__) do |file|
      app = Hawk::Rack.new(->(_) { [200, {}, file] }, client: @client)

      assert_equal __FILE__, app.call(Rack::MockRequest.env_for("/file"))[2].to_path
    end
  end

  def test_metadata_does_not_consume_request_body_or_include_credentials
    secret = SecureRandom.hex
    input = StringIO.new(secret)
    env = Rack::MockRequest.env_for("/safe?password=#{secret}", input: input)
    env["HTTP_AUTHORIZATION"] = "Bearer #{secret}"
    env["HTTP_COOKIE"] = "session=#{secret}"
    app = Hawk::Rack.new(->(_) { raise "failed" }, client: @client)
    original_position = input.pos

    assert_raises(RuntimeError) { app.call(env) }
    assert_equal original_position, input.pos
    refute_includes JSON.generate(@delivery.payloads), secret
  end
end

class RackEdgeCaseTest < HawkTest
  class BrokenEnvironment < Hash
    def slice(*)
      raise "metadata unavailable"
    end
  end

  class ClosingCallable < RackIntegrationTest::CallableBody
    def close
      raise "callable close failed"
    end
  end

  def test_inactive_or_disabled_clients_keep_native_application_results
    app = ->(_) { [201, {}, ["native"]] }
    Hawk.close
    assert_equal [201, {}, ["native"]], Hawk::Rack.new(app).call({})
    config = configuration
    config.integrations[:rack] = false
    client = Hawk::Client.new(config, delivery: RecordingDelivery.new)
    assert_equal [201, {}, ["native"]], Hawk::Rack.new(app, client: client).call({})
  end

  def test_opted_in_request_fields_are_detached_and_filtered
    delivery = RecordingDelivery.new
    config = configuration
    config.include_headers = config.include_cookies = config.include_request_body = true
    config.filter_parameters = ["cookie"]
    client = Hawk::Client.new(config, delivery: delivery)
    env = Rack::MockRequest.env_for("/")
    env.merge!("HTTP_AUTHORIZATION" => "secret", "HTTP_X_OPERATION" => "checkout", "HTTP_COOKIE" => "session=secret",
               "RAW_POST_DATA" => { "password" => "secret", "action" => "submit" })
    app = Hawk::Rack.new(->(_) { raise "request" }, client: client)

    assert_raises(RuntimeError) { app.call(env) }
    request = delivery.payloads.last.dig("addons", "request")
    assert_equal "[FILTERED]", request.dig("headers", "HTTP_AUTHORIZATION")
    assert_equal "checkout", request.dig("headers", "HTTP_X_OPERATION")
    assert_equal "[FILTERED]", request["cookies"]
    assert_equal({ "password" => "[FILTERED]", "action" => "submit" }, request["body"])
  end

  def test_bad_metadata_cannot_replace_an_application_failure
    delivery = RecordingDelivery.new
    client = Hawk::Client.new(configuration, delivery: delivery)
    error = RuntimeError.new("native")
    app = Hawk::Rack.new(->(_) { raise error }, client: client)

    assert_same error, assert_raises(RuntimeError) { app.call(BrokenEnvironment.new) }
    assert_equal({}, delivery.payloads.last.dig("addons", "request"))
  end

  def test_closing_the_default_client_during_a_request_keeps_native_failure
    delivery = RecordingDelivery.new
    client = Hawk::Client.new(configuration, delivery: delivery)
    Hawk.instance_variable_set(:@client, client)
    app = Hawk::Rack.new(lambda do |_|
      Hawk.close
      raise "closed during request"
    end)
    assert_raises(RuntimeError) { app.call(Rack::MockRequest.env_for("/closed")) }
    assert_empty delivery.payloads
  ensure
    Hawk.close
  end

  def test_body_protocols_preserve_optional_close_and_opaque_values
    client = Hawk::Client.new(configuration, delivery: RecordingDelivery.new)
    opaque = Object.new
    assert_same opaque, Hawk::Rack::Body.wrap(opaque, client: client, scope: client.current_scope.copy)
    body = Hawk::Rack::Body.wrap(["ok"], client: client, scope: client.current_scope.copy)
    assert_nil body.close
    callable = Hawk::Rack::Body.wrap(RackIntegrationTest::CallableBody.new, client: client,
                                                                            scope: client.current_scope.copy)
    assert_nil callable.close
  end

  def test_callable_close_errors_keep_their_scope_and_original_failure
    delivery = RecordingDelivery.new
    client = Hawk::Client.new(configuration, delivery: delivery)
    app = Hawk::Rack.new(->(_) { [200, {}, ClosingCallable.new] }, client: client)
    body = app.call(Rack::MockRequest.env_for("/close-callable"))[2]

    assert_equal "callable close failed", assert_raises(RuntimeError) { body.close }.message
    assert_equal "/close-callable", delivery.payloads.last.dig("addons", "request", "path")
  end
end
