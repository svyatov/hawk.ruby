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
