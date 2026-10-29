# frozen_string_literal: true

require "test_helper"
require "support/rails_capture_test"
require "action_cable"
require "action_cable/channel/test_case"

class HawkBrokenChannel < ActionCable::Channel::Base
  def fail_action
    Hawk.set_context(channel_only: true)
    raise "action failed"
  end

  def subscribed
    raise "subscribe failed"
  end

  def unsubscribed
    raise "unsubscribe failed"
  end
end

class HawkHandledChannel < HawkBrokenChannel
  attr_reader :handled

  rescue_from RuntimeError do |error|
    @handled = error
  end
end

class HawkBrokenConnection < ActionCable::Connection::Base
  def connect
    raise "connect failed"
  end

  def disconnect
    raise "disconnect failed"
  end
end

class RailsActionCableTest < RailsCaptureTest
  def test_channel_action_preserves_application_rescue_and_reports_once
    connection = ActionCable::Channel::ConnectionStub.new
    channel = HawkHandledChannel.new(connection, "fixture")
    channel.perform_action("action" => "fail_action", "password" => SecureRandom.hex)

    assert_equal "action failed", channel.handled.message
    assert_equal 1, @collector.events.size
    assert_equal "perform_action", @collector.events.last.dig("payload", "addons", "cable", "operation")
    assert_nil Hawk.client.current_scope.context["channel_only"]
  end

  def test_channel_subscription_and_unsubscription_preserve_errors
    channel = HawkBrokenChannel.new(ActionCable::Channel::ConnectionStub.new, "fixture")
    assert_raises(RuntimeError) { channel.subscribe_to_channel }
    assert_raises(RuntimeError) { channel.unsubscribe_from_channel }

    assert_equal 2, @collector.events.size
  end

  def test_connect_and_disconnect_preserve_errors_and_separate_invocations
    ActionCable.server.config.logger = Logger.new(File::NULL)
    connection = HawkBrokenConnection.new(ActionCable.server, Rack::MockRequest.env_for("/cable"))
    assert_raises(RuntimeError) { connection.send(:handle_open) }
    assert_raises(RuntimeError) { connection.send(:handle_close) }

    assert_equal(["connect failed", "disconnect failed"], @collector.events.map { |e| e.dig("payload", "title") })
  end
end
