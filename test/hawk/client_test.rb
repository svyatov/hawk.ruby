# frozen_string_literal: true

require "test_helper"

class ClientTest < HawkTest
  def test_context_precedence_and_detached_delivery
    config = configuration
    config.context = { "base" => "configured", "section" => "config" }
    client, delivery = capture_client(config)
    client.set_context(section: "scope")
    context = { section: "event", nested: ["original"] }
    identifier = client.capture_message("failed", context: context)
    context.fetch(:nested) << "changed"

    assert_kind_of String, identifier
    assert_equal "event", delivery.payloads.last.dig("context", "section")
    assert_equal "configured", delivery.payloads.last.dig("context", "base")
    assert_equal ["original"], delivery.payloads.last.dig("context", "nested")
  end

  def test_disabled_ignored_sampled_and_rejected_events_return_nil
    config = configuration
    config.token = nil
    client, delivery = capture_client(config)
    assert_nil client.capture_message("disabled")
    config.token = integration_token
    config.sample_rate = 0.0
    assert_nil client.capture_message("sampled")
    config.sample_rate = 1.0
    config.ignored_exceptions = ["StandardError"]
    assert_nil client.capture_exception(RuntimeError.new("ignored"))
    delivery.accept = false
    assert_nil client.capture_message("rejected")
    assert_empty delivery.payloads
  end

  def test_manual_capture_does_not_deduplicate_intentional_reports
    client, delivery = capture_client
    error = RuntimeError.new("twice")
    client.capture_exception(error)
    client.capture_exception(error)

    assert_equal 2, delivery.payloads.size
  end

  def test_user_precedence_and_anonymous_identifier
    client, delivery = capture_client
    client.capture_message("anonymous")
    client.capture_message("same anonymous")
    anonymous = delivery.payloads.first.fetch("user").fetch("id")
    assert_equal anonymous, delivery.payloads.last.dig("user", "id")
    client.set_user(id: "scope-user")
    client.capture_message("explicit", user: { id: "event-user" })
    assert_equal "event-user", delivery.payloads.last.dig("user", "id")
    client.capture_message("scoped")
    assert_equal "scope-user", delivery.payloads.last.dig("user", "id")
  end

  def test_capture_preserves_original_error_and_backtrace
    client, delivery = capture_client
    error = RuntimeError.new("original")
    error.set_backtrace(["original.rb:42"])
    observed = assert_raises(RuntimeError) { client.capture { raise error } }

    assert_same error, observed
    assert_equal ["original.rb:42"], observed.backtrace
    assert_equal 1, delivery.payloads.size
    assert_equal(7, client.capture { 7 })
  end

  def test_capture_preserves_normal_process_termination_without_reporting
    client, delivery = capture_client

    assert_raises(SystemExit) { client.capture { exit 7 } }
    assert_empty delivery.payloads
  end

  def test_reporting_failure_never_replaces_application_error
    client, delivery = capture_client
    delivery.failure = IOError.new("unavailable")
    error = RuntimeError.new("application failure")

    assert_same error, assert_raises(RuntimeError) { client.capture { raise error } }
    assert_nil client.capture_message("failed delivery")
  end

  def test_close_stops_acceptance
    client, delivery = capture_client

    assert client.close(timeout: 0.1)
    assert_nil client.capture_message("after close")
    assert_empty delivery.payloads
  end

  def test_successive_capture_wrappers_have_separate_report_ledgers
    client, delivery = capture_client
    error = RuntimeError.new("same object, separate attempts")
    2.times { assert_raises(RuntimeError) { client.capture { raise error } } }

    assert_equal 2, delivery.payloads.size
  end

  def test_manual_report_suppresses_a_later_automatic_duplicate
    client, delivery = capture_client
    error = RuntimeError.new("reported before propagation")
    assert_raises(RuntimeError) do
      client.capture do
        client.capture_exception(error)
        raise error
      end
    end

    assert_equal 1, delivery.payloads.size
  end

  def test_diagnostic_callback_cannot_reenter_capture_reporting
    config = configuration
    config.before_send = ->(_payload) {}
    client = nil
    notifications = 0
    config.diagnostic_callback = lambda do |_stats|
      notifications += 1
      client.capture_message("diagnostic callback")
    end
    client, delivery = capture_client(config)

    assert_nil client.capture_message("original event")
    assert_equal 1, notifications
    assert_empty delivery.payloads
  end
end
