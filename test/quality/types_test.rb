# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
require_relative "../../script/quality/types"

class TypeGateTest < HawkTest
  def setup
    @directory = Dir.mktmpdir("hawk-types")
    FileUtils.mkdir_p(File.join(@directory, "lib"))
    File.write(File.join(@directory, "lib/example.rb"), "module Example; end\n")
    @row = { "File" => "lib/example.rb", "Status" => "success", "Typed calls" => "3",
             "Untyped calls" => "0", "All calls" => "3" }
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_complete_analysis_passes_with_integer_call_counts
    assert HawkQuality::Types.verify!(@directory, [@row])
  end

  def test_missing_files_untyped_calls_failed_analysis_and_duplicate_rows_fail
    [[], [@row.merge("Untyped calls" => "1")], [@row.merge("Status" => "error")], [@row, @row]].each do |rows|
      assert_raises(HawkQuality::Failure) { HawkQuality::Types.verify!(@directory, rows) }
    end
  end

  def test_a_new_untracked_runtime_file_cannot_escape_analysis
    File.write(File.join(@directory, "lib/forgotten.rb"), "module Forgotten; end\n")

    assert_raises(HawkQuality::Failure) { HawkQuality::Types.verify!(@directory, [@row]) }
  end

  def test_invalid_counts_do_not_pass_as_rounded_percentages
    %w[-1 nonsense 0.0].each do |count|
      row = @row.merge("Untyped calls" => count, "Typed %" => "100")
      assert_raises(HawkQuality::Failure) { HawkQuality::Types.verify!(@directory, [row]) }
    end
  end

  def test_unchecked_casts_untyped_annotations_and_blanket_suppressions_fail
    ["value = input #: String", "# @type var input: untyped", "# steep:ignore:start",
     "# rubocop:disable all"].each do |source|
      File.write(File.join(@directory, "lib/example.rb"), "#{source}\n")
      assert_raises(HawkQuality::Failure) { HawkQuality::Types.verify!(@directory, [@row]) }
    end
  end

  def test_steep_internal_crashes_are_failures_even_with_success_exit
    assert_raises(HawkQuality::Failure) { HawkQuality::Types.verify_output!("No type error\nFATAL: crash") }
    assert HawkQuality::Types.verify_output!("No type error detected\n")
  end

  def test_fixture_processes_exit_nonzero_for_missing_and_untyped_analysis
    script = "HawkQuality::Types.verify!(ARGV.fetch(0), JSON.parse(ARGV.fetch(1)))"
    path = File.expand_path("../../script/quality/types.rb", __dir__)
    [[[], 1], [[@row.merge("Untyped calls" => "1")], 1], [[@row], 0]].each do |rows, expected|
      _out, error, status = Open3.capture3(RbConfig.ruby, "-rjson", "-r#{path}", "-e", script,
                                           @directory, JSON.generate(rows))
      assert_equal expected, status.exitstatus, error
    end
  end
end
