# frozen_string_literal: true

require "test_helper"

class ScopeTest < HawkTest
  def test_nested_scope_restores_context_after_error
    client, delivery = capture_client
    client.set_context(section: "outer")
    assert_raises(RuntimeError) do
      client.with_scope do |scope|
        scope.set_context(section: "inner")
        client.capture_message("inside")
        raise "leave"
      end
    end
    client.capture_message("outside")

    assert_equal "inner", delivery.payloads.first.dig("context", "section")
    assert_equal "outer", delivery.payloads.last.dig("context", "section")
  end

  def test_fibers_and_threads_have_independent_scopes
    client, delivery = capture_client
    client.set_context(section: "main")
    fiber = Fiber.new do
      client.set_context(section: "fiber")
      Fiber.yield
      client.capture_message("fiber")
    end
    fiber.resume
    Thread.new do
      client.set_context(section: "thread")
      client.capture_message("thread")
    end.join
    client.capture_message("main")
    fiber.resume

    assert_equal(%w[thread main fiber], delivery.payloads.map { |payload| payload.dig("context", "section") })
  end

  def test_clients_do_not_share_scope_storage
    first, first_delivery = capture_client
    second, second_delivery = capture_client
    first.set_context(project: "first")
    second.set_context(project: "second")
    first.capture_message("first")
    second.capture_message("second")

    assert_equal "first", first_delivery.payloads.last.dig("context", "project")
    assert_equal "second", second_delivery.payloads.last.dig("context", "project")
  end

  def test_nested_context_replacement_is_shallow
    client, delivery = capture_client
    client.set_context(nested: { original: true })
    client.capture_message("replace", context: { nested: { replacement: true } })

    assert_equal({ "replacement" => true }, delivery.payloads.last.dig("context", "nested"))
  end
end
