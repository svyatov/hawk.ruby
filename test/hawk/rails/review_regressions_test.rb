# frozen_string_literal: true

require "test_helper"
require "support/rails_capture"

class RailsReviewRegressionsTest < RailsCaptureTest
  def teardown
    Rails.application.config.filter_parameters = [:pin]
    super
  end

  def test_headers_do_not_bypass_the_cookie_exclusion
    Hawk.client.configuration.include_headers = true
    env = Rack::MockRequest.env_for("/headers", "HTTP_COOKIE" => "session=private",
                                                "HTTP_X_OPERATION" => "checkout")
    assert_raises(RuntimeError) { Hawk::Rack.new(->(_) { raise "headers" }).call(env) }
    request = @collector.events.last.dig("payload", "addons", "request")

    assert_equal "checkout", request.dig("headers", "HTTP_X_OPERATION")
    refute request.fetch("headers").key?("HTTP_COOKIE")
    refute request.key?("cookies")
  end

  def test_anchored_parameter_filters_use_the_original_tree_once
    calls = 0
    Rails.application.config.filter_parameters = [
      /\Aperson\.ssn\z/,
      lambda do |key, value, original|
        next unless key == "label"

        calls += 1
        value.replace(original.fetch("replacement"))
      end
    ]
    initialize_hawk
    params = { "person" => { "ssn" => "private" }, "label" => "original", "replacement" => "safe" }
    env = Rack::MockRequest.env_for("/parameters")
    env["action_dispatch.request.parameters"] = params
    assert_raises(RuntimeError) { Hawk::Rack.new(->(_) { raise "parameters" }).call(env) }
    filtered = @collector.events.last.dig("payload", "addons", "request", "params")

    assert_equal "[FILTERED]", filtered.dig("person", "ssn")
    assert_equal "safe", filtered.fetch("label")
    assert_equal 1, calls
    assert_equal "original", params.fetch("label")
  end

  def test_breadcrumb_filter_blocks_are_not_reapplied_during_event_assembly
    configure_reversing_filter
    Hawk.add_breadcrumb(message: "lookup", data: { ssn: "identity" })
    Hawk.capture_message("with breadcrumb")

    assert_equal "ytitnedi", Hawk.client.current_scope.breadcrumbs.last.dig("data", "ssn")
    assert_equal "ytitnedi", @collector.events.last.dig("payload", "breadcrumbs", 0, "data", "ssn")
  end

  def test_propagated_context_is_not_transformed_again_after_snapshots
    configure_reversing_filter
    Hawk.set_context(person: { ssn: "identity" })
    Hawk.set_user(id: "42", ssn: "customer")
    metadata = Hawk::JobContext.dump(Hawk.client)
    Hawk.client.with_boundary(kind: :job, metadata: {}) do
      Hawk::JobContext.apply(Hawk.client, metadata)
      Hawk.with_scope { Hawk.capture_message("propagated") }
      assert_equal metadata, Hawk::JobContext.dump(Hawk.client)
      Hawk.capture_message("override", context: { person: { ssn: "new" } }, user: { ssn: "new user" })
    end
    first = @collector.events[-2].fetch("payload")
    assert_equal "ytitnedi", first.dig("context", "person", "ssn")
    assert_equal "remotsuc", first.dig("user", "ssn")
    assert_equal "wen", @collector.events.last.dig("payload", "context", "person", "ssn")
    assert_equal "resu wen", @collector.events.last.dig("payload", "user", "ssn")
  end

  def test_standalone_reports_continue_beyond_the_duplicate_limit
    300.times { |index| Rails.error.report(RuntimeError.new("standalone #{index}"), handled: true) }

    assert_equal 300, @collector.events.size
    refute Hawk.client.diagnostics.snapshot.key?(:duplicate_overflow)
  end

  def test_logical_array_arguments_and_event_overrides_receive_one_filter_application
    configure_reversing_filter
    Hawk.client.with_boundary(kind: :job,
                              metadata: { "job" => { "arguments" => [
                                { "ssn" => "private" }, "value"
                              ] } }) do
      Hawk.capture_message("arguments")
    end

    assert_equal [{ "ssn" => "etavirp" }, "value"], @collector.events.last.dig("payload", "addons", "job", "arguments")
  end

  def test_a_key_mask_still_applies_to_producer_filtered_values
    Rails.application.config.filter_parameters = [:person]
    initialize_hawk
    Hawk::JobContext.apply(Hawk.client, { "version" => 1, "context" => { "person" => { "ssn" => "safe" } } })
    Hawk.capture_message("masked")

    assert_equal "[FILTERED]", @collector.events.last.dig("payload", "context", "person")
  end

  private

  def configure_reversing_filter
    Rails.application.config.filter_parameters = [->(key, value) { value.reverse! if key == "ssn" }]
    initialize_hawk
  end
end
