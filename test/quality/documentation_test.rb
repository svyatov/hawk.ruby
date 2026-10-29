# frozen_string_literal: true

require "test_helper"
require "yard"
require_relative "../../script/quality/documentation"

class DocumentationGateTest < HawkTest
  def teardown
    YARD::Registry.clear
  end

  def problems(source)
    YARD::Registry.clear
    YARD.parse_string(source)
    stats = YARD::CLI::Stats.new(false)
    stats.parse_arguments("--no-yardopts", "--hide-api", "private")
    HawkQuality::Documentation.problems(stats.all_objects)
  end

  def test_undocumented_public_objects_fail
    assert_includes problems("class Example; end"), "Example: missing documentation"
  end

  def test_new_parameters_need_typed_tags
    result = problems(<<~RUBY)
      # Example API.
      class Example
        # Runs work.
        # @return [void]
        def run(mode:, retries: 1); end
      end
    RUBY
    assert_includes result, "Example#run: missing typed @param mode"
    assert_includes result, "Example#run: missing typed @param retries"
  end

  def test_renamed_parameters_leave_stale_tags
    result = problems(<<~RUBY)
      # Example API.
      class Example
        # @param old_name [String] obsolete name
        # @return [void]
        def run(new_name); end
      end
    RUBY
    assert_includes result, "Example#run: @param old_name is not in the signature"
  end

  def test_methods_need_typed_returns
    result = problems("# Example API.\nclass Example\n# Runs work.\ndef run; end\nend")
    assert_includes result, "Example#run: missing typed @return"
  end

  def test_internal_namespaces_and_private_methods_are_excluded
    assert_empty problems(<<~RUBY)
      # @api private
      class Internal
        def run(secret); end
      end
      # Example API.
      class Example
        private
        def hidden(secret); end
      end
    RUBY
  end

  def test_reference_tags_attributes_and_anonymous_blocks_pass
    assert_empty problems(<<~RUBY)
      # Example API.
      class Example
        # @return [String] name
        attr_accessor :name
        # @param value [String] input
        # @return [String] result
        def run(value, &); end
        # (see #run)
        def again(value, &); end
      end
    RUBY
  end
end
