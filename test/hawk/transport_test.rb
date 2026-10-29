# frozen_string_literal: true

require "test_helper"
require "support/collector"

class TransportTest < HawkTest
  def setup
    @collector = Collector.new
    @config = configuration
    @config.endpoint = @collector.url
    @config.read_timeout = 0.1
  end

  def teardown
    @collector.close
  end

  def test_accepts_only_valid_hawk_success_response
    transport = Hawk::Transport.new(@config)

    assert_equal :accepted, transport.send(JSON.generate("payload" => "local test"))
    assert_equal [{ "payload" => "local test" }], @collector.events
    @collector.body = JSON.generate("code" => 200, "error" => true, "message" => "secret response")
    assert_equal :failed, transport.send("{}")
  end

  def test_invalid_or_oversized_response_fails_without_retrying
    @collector.body = "not json"
    assert_equal :failed, Hawk::Transport.new(@config).send("{}")
    @collector.body = "a" * 16_385
    assert_equal :failed, Hawk::Transport.new(@config).send("{}")
    assert_equal 2, @collector.events.size
  end

  def test_redirect_does_not_forward_token
    @collector.status = 302
    @collector.headers = { "Location" => "#{@collector.url}/different" }

    assert_equal :failed, Hawk::Transport.new(@config).send("{}")
    assert_equal 1, @collector.events.size
  end

  def test_rate_limit_cooldown_prevents_another_request
    @collector.status = 429
    @collector.headers = { "Retry-After" => "60" }
    transport = Hawk::Transport.new(@config)

    assert_equal :limited, transport.send("{}")
    refute transport.available?
    assert_equal :limited, transport.send("{}")
    assert_equal 1, @collector.events.size
  end

  def test_hawk_402_limits_use_configured_cooldown
    @collector.status = 402
    transport = Hawk::Transport.new(@config)

    assert_equal :limited, transport.send("{}")
    refute transport.available?
  end

  def test_timeout_does_not_repeat_ambiguous_post
    @collector.delay = 0.2

    assert_equal :failed, Hawk::Transport.new(@config).send("{}")
    assert_equal 1, @collector.events.size
  end
end
