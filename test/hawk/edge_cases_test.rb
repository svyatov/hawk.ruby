# frozen_string_literal: true

require "test_helper"

class CoreEdgeCasesTest < HawkTest
  class BrokenDelivery < RecordingDelivery
    def flush(timeout:)
      raise IOError, "flush unavailable: #{timeout}"
    end

    def close(timeout:)
      raise IOError, "close unavailable: #{timeout}"
    end
  end

  class BrokenIntrospection < RuntimeError
    def backtrace_locations
      raise "broken locations"
    end

    def cause
      raise "broken cause"
    end
  end

  class BrokenMetadata < Hash
    def all?(*)
      raise "metadata reader failed"
    end
  end

  def test_broken_persisted_job_metadata_is_dropped
    assert_nil Hawk::JobContext.load(BrokenMetadata.new)
  end

  def teardown
    Hawk.close
  end

  def test_module_facade_delegates_capture_and_scope_operations
    client, delivery = capture_client
    Hawk.instance_variable_set(:@client, client)
    Hawk.set_context(section: "parent")
    Hawk.set_user(id: "explicit")
    Hawk.with_scope do
      Hawk.set_context(section: "child")
      assert Hawk.capture_exception(RuntimeError.new("facade"))
    end

    assert_equal "child", delivery.payloads.last.dig("context", "section")
    assert_equal "parent", client.current_scope.context["section"]
    Hawk.set_user(nil)
    assert_nil client.current_scope.user
  end

  def test_uninitialized_facade_is_inert_and_does_not_skip_blocks
    Hawk.close
    assert_nil Hawk.capture_exception(RuntimeError.new("disabled"))
    assert_nil Hawk.set_context(section: "ignored")
    assert_nil Hawk.set_user(id: "ignored")
    assert_nil Hawk.add_breadcrumb(message: "ignored")
    assert Hawk.flush
    assert_nil Hawk::Breadcrumbs.client(:logger)
    assert_nil Hawk::ProcessHooks.report_exit(RuntimeError.new("ignored"))
  end

  def test_broken_delivery_deadlines_are_reported_as_false
    client = Hawk::Client.new(configuration, delivery: BrokenDelivery.new)

    refute client.flush
    refute client.close
  end

  def test_disabled_client_does_not_collect_breadcrumbs_or_process_exits
    client, = capture_client
    Hawk.instance_variable_set(:@client, client)
    client.configuration.global_errors = false
    assert_nil Hawk::ProcessHooks.report_exit(RuntimeError.new("ignored"))
    client.close
    client.add_breadcrumb(message: "after close")

    assert_empty client.current_scope.breadcrumbs
    assert_nil Hawk::Breadcrumbs.client(:http)
  end

  def test_failure_diagnostics_never_replace_the_operation_result
    diagnostics = Hawk::Diagnostics.new(->(_) { raise "diagnostic failed" })
    assert_nil diagnostics.increment(:failed)
    assert_equal 1, diagnostics.snapshot[:failed]
  end

  def test_json_boundary_rejects_unsupported_keys_and_broken_introspection
    broken = Object.new
    def broken.class
      raise "broken class reader"
    end

    assert_equal "[Unsupported]", Hawk::JSONValue.normalize(BasicObject.new)
    assert_equal "[Unavailable]", Hawk::JSONValue.normalize(broken)
    assert_equal({ "valid" => true }, Hawk::JSONValue.object({ Object.new => "ignored", "valid" => true }))
  end

  def test_broken_exception_introspection_does_not_prevent_reporting
    client, delivery = capture_client
    assert client.capture_exception(BrokenIntrospection.new("still useful"))

    assert_equal "still useful", delivery.payloads.last["title"]
    assert_empty delivery.payloads.last["backtrace"]
  end

  def test_disabled_transport_and_https_configuration
    config = Hawk::Configuration.new
    config.token = nil
    transport = Hawk::Transport.new(config)
    refute transport.available?
    assert_equal :limited, transport.send("{}")
    config = configuration
    config.endpoint = "https://collector.example.test/errors"

    assert_nil config.validate!
    assert_equal "collector.example.test", config.collector_uri.host
  end

  def test_job_context_filters_snapshots_without_framework_dependencies
    client, = capture_client
    client.set_context(section: "explicit", password: "hidden")
    data = Hawk::JobContext.dump(client)

    assert_equal "[FILTERED]", data.dig("context", "password")
    assert_nil data["user"]
    client.configuration.propagate_job_context = false
    Hawk::JobContext.apply(client, { "version" => 1, "context" => { "injected" => true } })
    assert_nil client.current_scope.context["injected"]
  end

  def test_bad_job_context_drops_propagation_and_preserves_execution_data
    client, = capture_client
    client.configuration.framework_filter = ->(_) { raise "filter failed" }

    assert_nil Hawk::JobContext.dump(client)
    assert_nil Hawk::JobContext.load({ "version" => 1, "context" => "wrong type" })
  end

  def test_non_string_integration_identifier_is_rejected
    token = Base64.strict_encode64(JSON.generate("integrationId" => 12, "secret" => "secret"))

    assert_raises(Hawk::ConfigurationError) { Hawk::Token.decode(token) }
  end
end
