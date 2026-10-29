# frozen_string_literal: true

require "test_helper"

class FilterLifecycleTest < HawkTest
  def test_framework_replacements_can_remove_or_mask_previously_filtered_fields
    client, delivery = capture_client
    Hawk::JobContext.apply(client, { "version" => 1, "context" => { "person" => { "ssn" => "safe" } } })
    [nil, "[FILTERED]", { "person" => "[FILTERED]" }, { "person" => { "changed" => "safe" } }].each do |replacement|
      client.configuration.framework_filter = ->(payload) { payload.merge("context" => replacement) }
      client.capture_message("replacement")

      assert_equal({ "context" => replacement }, delivery.payloads.last.slice("context"))
    end
    client.configuration.framework_filter = ->(payload) { payload.except("context") }
    client.capture_message("removed")
    refute delivery.payloads.last.key?("context")
  end

  def test_new_scope_values_replace_the_producer_filtered_state
    client, delivery = capture_client
    Hawk::JobContext.apply(client,
                           { "version" => 1, "context" => { "person" => "safe" }, "user" => { "id" => "safe" } })
    client.configuration.framework_filter = lambda { |payload|
      payload.transform_values do |value|
        value == {} ? value : "new"
      end
    }
    client.set_context(person: "raw")
    client.set_user(id: "raw")
    client.capture_message("updated")

    assert_equal "new", delivery.payloads.last.fetch("context")
    assert_equal "new", delivery.payloads.last.fetch("user")
  end
end
