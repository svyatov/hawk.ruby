# frozen_string_literal: true

require "test_helper"

class FilterTest < HawkTest
  def test_recursively_filters_without_modifying_input
    input = { "password" => "sensitive", "nested" => [{ "api_key" => "hidden", "ok" => 1 }] }
    result = Hawk::Filter.new(configuration).call(input)

    assert_equal "[FILTERED]", result.fetch("password")
    assert_equal "[FILTERED]", result.fetch("nested").first.fetch("api_key")
    assert_equal 1, result.fetch("nested").first.fetch("ok")
    assert_equal "sensitive", input.fetch("password")
  end

  def test_custom_string_and_regexp_filters
    config = configuration
    config.filter_parameters = ["email", /address/i]
    result = Hawk::Filter.new(config).call({ "user_email" => "a@b", "Address" => "hidden", "count" => 3 })

    assert_equal({ "user_email" => "[FILTERED]", "Address" => "[FILTERED]", "count" => 3 }, result)
  end
end
