# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"
require "open3"
require "rbconfig"
require_relative "../../script/quality/coverage"

class CoverageGateTest < HawkTest
  def setup
    @directory = Dir.mktmpdir("hawk-coverage")
    @source = { "lib/example.rb" => "abc123" }
    @manifest = { "revision" => "commit", "sources" => @source, "run" => "fresh", "lane" => "core" }
    @report = { "coverage" => { "/fixture/lib/example.rb" => { "lines" => [1, nil, 2],
                                                               "branches" => { "branch" => { "then" => 1 } } } } }
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_matching_fresh_manifests_are_accepted
    assert HawkQuality::Coverage.verify_manifest!(@manifest, revision: "commit", sources: @source, run: "fresh")
  end

  def test_wrong_revision_changed_sources_and_stale_runs_are_rejected
    [{ "revision" => "old" }, { "sources" => {} }, { "run" => "stale" }].each do |change|
      assert_raises(HawkQuality::Failure) do
        HawkQuality::Coverage.verify_manifest!(@manifest.merge(change), revision: "commit", sources: @source,
                                                                        run: "fresh")
      end
    end
  end

  def test_missing_lanes_cannot_pass_the_coverage_merge
    assert_raises(HawkQuality::Failure) { HawkQuality::Coverage.verify_lanes!([@manifest], %w[core rails]) }
  end

  def test_uncovered_lines_and_branches_fail
    assert HawkQuality::Coverage.verify_counts!(@report.fetch("coverage"), ["lib/example.rb"])
    @report["coverage"].values.first["lines"][0] = 0
    assert_raises(HawkQuality::Failure) do
      HawkQuality::Coverage.verify_counts!(@report.fetch("coverage"), ["lib/example.rb"])
    end
    @report["coverage"].values.first["lines"][0] = 1
    @report["coverage"].values.first["branches"]["branch"]["then"] = 0
    assert_raises(HawkQuality::Failure) do
      HawkQuality::Coverage.verify_counts!(@report.fetch("coverage"), ["lib/example.rb"])
    end
  end

  def test_a_missing_runtime_file_cannot_pass
    assert_raises(HawkQuality::Failure) { HawkQuality::Coverage.verify_counts!({}, ["lib/example.rb"]) }
  end

  def test_stale_fixture_process_exits_nonzero
    script = 'HawkQuality::Coverage.verify_manifest!({}, revision: "new", sources: {}, run: "fresh")'
    path = File.expand_path("../../script/quality/coverage.rb", __dir__)
    _out, error, status = Open3.capture3(RbConfig.ruby, "-r#{path}", "-e", script)

    assert_equal 1, status.exitstatus, error
  end
end
