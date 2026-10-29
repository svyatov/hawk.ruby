# frozen_string_literal: true

require "test_helper"

class JobContextTest < HawkTest
  def test_rejects_untrusted_metadata_without_invoking_conversion_methods
    invalid = [nil, [], { "version" => 2 }, { "version" => 1, "context" => Object.new },
               { "version" => 1, "context" => { symbol: true } },
               { "version" => 1, "context" => { "value" => Float::NAN } },
               { "version" => 1, "context" => { "large" => "x" * 8192 } }]
    invalid.each { |value| assert_nil Hawk::JobContext.load(value) }
  end

  def test_rejects_cycles_and_deep_values
    cycle = { "version" => 1, "context" => {} }
    cycle["context"]["cycle"] = cycle

    assert_nil Hawk::JobContext.load(cycle)
    nested = 10.times.reduce({}) { |value, _| { "next" => value } }
    assert_nil Hawk::JobContext.load({ "version" => 1, "context" => nested })
  end
end
