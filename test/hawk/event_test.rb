# frozen_string_literal: true

require "test_helper"

class EventTest < HawkTest
  class BrokenMessage < RuntimeError
    def message
      raise "broken conversion"
    end
  end

  class CyclicCause < RuntimeError
    def cause
      self
    end
  end

  def test_event_matches_hawk_envelope
    error = ZeroDivisionError.new("divided by 0")
    error.set_backtrace(["#{__FILE__}:1:in 'test'"])
    event = Hawk::Event.new(configuration: configuration, id: "local-id", exception: error,
                            context: { "password" => "hidden", "section" => "checkout" })
    data = JSON.parse(event.encode)
    payload = data.fetch("payload")

    assert_equal "errors/ruby", data.fetch("catcherType")
    assert_equal integration_token, data.fetch("token")
    assert_equal "ZeroDivisionError", payload.fetch("type")
    assert_equal "divided by 0", payload.fetch("title")
    assert_equal "[FILTERED]", payload.dig("context", "password")
    assert_equal "local-id", payload.dig("addons", "event_id")
    assert_equal "0.1.0", payload.fetch("catcherVersion")
    assert_operator event.encode.bytesize, :<=, 262_144
  end

  def test_hook_sees_filtered_payload_and_can_replace_or_drop
    config = configuration
    config.before_send = lambda do |payload|
      assert_equal "[FILTERED]", payload.dig("context", "password")
      payload.merge("title" => "changed")
    end
    event = Hawk::Event.new(configuration: config, id: "id", message: "original", context: { "password" => "hidden" })

    assert_equal "changed", JSON.parse(event.encode).dig("payload", "title")
    config.before_send = ->(_payload) {}
    assert_nil event.encode
    config.before_send = ->(_payload) { false }
    assert_nil event.encode
  end

  def test_hook_failure_or_invalid_replacement_drops_event
    config = configuration
    event = Hawk::Event.new(configuration: config, id: "id", message: "original")
    [->(_) { raise "hook failure" }, ->(_) { [] }, ->(_) { {} }].each do |hook|
      config.before_send = hook

      assert_nil event.encode
    end
  end

  def test_oversized_context_is_trimmed_without_removing_title
    context = (1..100).to_h { |index| [index.to_s, "a" * 8192] }
    event = Hawk::Event.new(configuration: configuration, id: "id", message: "large", context: context)
    encoded = event.encode

    assert_operator encoded.bytesize, :<=, 262_144
    assert_equal "large", JSON.parse(encoded).dig("payload", "title")
    assert_equal 100, context.size
  end

  def test_broken_messages_and_cyclic_causes_do_not_break_capture
    broken = Hawk::Event.new(configuration: configuration, id: "id", exception: BrokenMessage.new)
    cyclic = Hawk::Event.new(configuration: configuration, id: "id", exception: CyclicCause.new("cycle"))

    assert_equal "EventTest::BrokenMessage", JSON.parse(broken.encode).dig("payload", "title")
    assert_equal 1, JSON.parse(cyclic.encode).dig("payload", "addons", "causes").size
  end
end
