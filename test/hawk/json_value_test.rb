# frozen_string_literal: true

require "test_helper"

class JSONValueTest < HawkTest
  class UnsafeValue
    def inspect
      raise "inspect must not run"
    end

    def to_json(*)
      raise "to_json must not run"
    end
  end

  def test_normalizes_without_executing_custom_conversions
    input = { section: "checkout", object: UnsafeValue.new, infinite: Float::INFINITY }
    value = Hawk::JSONValue.normalize(input)

    assert_equal "checkout", value.fetch("section")
    assert_equal "[JSONValueTest::UnsafeValue]", value.fetch("object")
    assert_nil value.fetch("infinite")
    assert input.key?(:section)
  end

  def test_cycles_depth_and_container_width_are_bounded
    cyclic = []
    cyclic << cyclic
    deep = "end"
    12.times { deep = [deep] }

    assert_equal ["[Circular]"], Hawk::JSONValue.normalize(cyclic)
    assert_includes JSON.generate(Hawk::JSONValue.normalize(deep)), "[Truncated]"
    assert_equal 100, Hawk::JSONValue.normalize(Array.new(101, 1)).size
  end

  def test_invalid_encodings_and_large_strings_are_safe_json
    input = { text: "\xff".b, large: "☃" * 5000 }
    value = Hawk::JSONValue.normalize(input)

    assert value.fetch("text").valid_encoding?
    assert_operator value.fetch("large").bytesize, :<=, 8192
    assert value.fetch("large").valid_encoding?
    assert_kind_of String, JSON.generate(value)
  end

  def test_repeated_cycles_do_not_clear_the_parent_visit_marker
    input = []
    input.push(input, input)

    assert_equal ["[Circular]", "[Circular]"], Hawk::JSONValue.normalize(input)
  end
end
