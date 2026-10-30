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
    assert_equal "0.1.2", payload.fetch("catcherVersion")
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

  def test_release_and_framework_filter_result_are_preserved
    config = configuration
    config.release = "release-42"
    event = Hawk::Event.new(configuration: config, id: "id", message: "release")
    assert_equal "release-42", JSON.parse(event.encode).dig("payload", "release")
    config.framework_filter = ->(_) { false }

    assert_nil event.encode
  end

  def test_oversized_frames_are_reduced_after_optional_data
    config = configuration
    config.before_send = lambda do |payload|
      payload.merge("backtrace" => Array.new(100) { { "file" => "x" * 8192, "function" => "y" * 8192 } })
    end
    encoded = Hawk::Event.new(configuration: config, id: "id", message: "large frames").encode

    assert_operator encoded.bytesize, :<=, 262_144
    assert_equal 1, JSON.parse(encoded).dig("payload", "backtrace").size
  end

  def test_untrimmable_hook_fields_are_dropped_without_sending_oversized_data
    config = configuration
    config.before_send = ->(payload) { payload.merge((1..90).to_h { |number| [number.to_s, "x" * 8192] }) }

    assert_nil Hawk::Event.new(configuration: config, id: "id", message: "too large").encode
  end

  def test_source_snippets_and_cause_arrays_are_trimmed_safely
    config = configuration
    config.before_send = lambda do |payload|
      payload.merge("backtrace" => [{ "sourceCode" => "x" * 8192 }, "foreign frame"],
                    "addons" => { "causes" => Array.new(100) { { "message" => "x" * 8192 } } })
    end
    encoded = Hawk::Event.new(configuration: config, id: "id", message: "large causes").encode

    assert_operator encoded.bytesize, :<=, 262_144
    refute JSON.parse(encoded).dig("payload", "backtrace").first.key?("sourceCode")
  end

  def test_non_object_addons_from_a_hook_do_not_break_size_trimming
    config = configuration
    config.before_send = lambda do |payload|
      payload.merge("addons" => false, "backtrace" => Array.new(100) { "frame" * 1500 })
    end
    encoded = Hawk::Event.new(configuration: config, id: "id", message: "foreign addons").encode

    assert_operator encoded.bytesize, :<=, 262_144
    assert_equal "foreign addons", JSON.parse(encoded).dig("payload", "title")
  end
end
