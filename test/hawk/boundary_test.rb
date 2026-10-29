# frozen_string_literal: true

require "test_helper"

class BoundaryTest < HawkTest
  def test_nested_automatic_handlers_report_one_failure
    client, delivery = capture_client
    error = RuntimeError.new("one failure")
    Hawk::Boundary.run(client, kind: :job, metadata: {}) do
      Hawk::Boundary.run(client, kind: :active_job, metadata: {}) do
        client.report(error, mechanism: "active_job")
      end
      client.report(error, mechanism: "sidekiq")
    end

    assert_equal 1, delivery.payloads.size
  end

  def test_successive_attempts_of_same_error_remain_reportable
    client, delivery = capture_client
    error = RuntimeError.new("retry")
    2.times do
      Hawk::Boundary.run(client, kind: :job, metadata: {}) { client.report(error, mechanism: "job") }
    end

    assert_equal 2, delivery.payloads.size
  end

  def test_fresh_boundaries_reset_context_and_anonymous_identity
    client, delivery = capture_client
    2.times do |attempt|
      Hawk::Boundary.run(client, kind: :request, metadata: { "request" => { "method" => "GET" } }) do
        client.capture_message("request-#{attempt}")
        client.set_context(leak: "private")
      end
    end

    assert_nil delivery.payloads.last.dig("context", "leak")
    refute_equal delivery.payloads.first.dig("user", "id"), delivery.payloads.last.dig("user", "id")
    assert_equal "GET", delivery.payloads.last.dig("addons", "request", "method")
  end

  def test_automatic_registry_is_bounded
    client, delivery = capture_client
    Hawk::Boundary.run(client, kind: :job, metadata: {}) do
      257.times { |number| client.report(RuntimeError.new(number.to_s), mechanism: "job") }
    end

    assert_equal 256, delivery.payloads.size
    assert_equal 1, client.diagnostics.snapshot.fetch(:duplicate_overflow)
  end
end
