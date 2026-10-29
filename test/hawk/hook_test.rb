# frozen_string_literal: true

require "test_helper"
require "support/collector"

class HookIsolationTest < HawkTest
  def test_event_hooks_cannot_replace_an_escaping_application_exception
    [LoadError, SyntaxError, Exception].each do |error_class|
      %i[before_send framework_filter].each do |name|
        config = configuration
        config.public_send("#{name}=", ->(_) { raise error_class, "hook failure" })
        client, delivery = capture_client(config)
        original = RuntimeError.new("application failure")

        assert_same original, assert_raises(RuntimeError) { client.capture { raise original } }
        assert_empty delivery.payloads
      end
    end
  end

  def test_breadcrumb_and_context_hooks_cannot_interrupt_callers
    [LoadError, SyntaxError].each do |error_class|
      client, = capture_client
      client.configuration.before_breadcrumb = ->(_) { raise error_class, "breadcrumb failure" }
      assert_nil client.add_breadcrumb(message: "drop")
      assert_empty client.current_scope.breadcrumbs
      client.configuration.before_breadcrumb = nil
      client.configuration.framework_filter = ->(_) { raise error_class, "context failure" }
      assert_nil client.add_breadcrumb(message: "drop through framework filter")
      assert_empty client.current_scope.breadcrumbs
      assert_nil Hawk::JobContext.dump(client)
    end
  end

  def test_diagnostic_hook_failures_do_not_kill_the_delivery_worker
    collector = Collector.new
    config = configuration
    config.endpoint = collector.url
    config.diagnostic_callback = ->(_) { raise LoadError, "diagnostic failure" }
    client = Hawk::Client.build(config)
    assert client.capture_message("first")
    assert client.flush(timeout: 1.0)
    assert client.capture_message("second")
    assert client.flush(timeout: 1.0)
    titles = collector.events.map { |event| event.dig("payload", "title") }
    assert_equal %w[first second], titles
    assert_equal 2, client.diagnostics.snapshot[:sent]
  ensure
    client&.close(timeout: 1.0)
    collector&.close
  end

  def test_invalid_filter_configuration_drops_capture_without_interrupting_application_code
    config = configuration
    config.filter_parameters = nil
    client, delivery = capture_client(config)
    assert_nil client.capture_message("invalid filters")
    assert_nil client.add_breadcrumb(message: "invalid filters")
    assert_nil Hawk::JobContext.dump(client)
    assert_equal 2, client.diagnostics.snapshot[:filtered]
    assert_empty delivery.payloads
  end
end
