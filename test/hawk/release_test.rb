# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "rbconfig"

class ReleaseTest < HawkTest
  def test_explicit_revision_takes_precedence
    config = configuration
    config.release = "deploy-42"
    config.detect_release = true

    assert_equal "deploy-42", Hawk::Release.detect(config)
  end

  def test_detection_requires_opt_in
    config = configuration
    config.release = nil

    assert_nil Hawk::Release.detect(config)
  end

  def test_git_revision_matches_checkout
    config = configuration
    config.release = nil
    config.detect_release = true
    expected, = Open3.capture2("git", "rev-parse", "HEAD")

    assert_equal expected.strip, Hawk::Release.detect(config)
  end

  def test_git_failures_and_empty_output_return_no_release
    ["exit 1", "exit 0"].each do |program|
      with_git(program) { assert_nil Hawk::Release.git_revision }
    end
    original = ENV.fetch("PATH")
    ENV["PATH"] = "/nonexistent-hawk-path"
    assert_nil Hawk::Release.git_revision
  ensure
    ENV["PATH"] = original if original
  end

  def test_slow_git_process_is_killed_and_reaped_within_the_deadline
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    with_git("sleep 5") { assert_nil Hawk::Release.git_revision }

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 3
  end

  private

  def with_git(program)
    original = ENV.fetch("PATH")
    Dir.mktmpdir("hawk-git") do |directory|
      path = File.join(directory, "git")
      File.write(path, "#!#{RbConfig.ruby}\n#{program}\n")
      File.chmod(0o700, path)
      ENV["PATH"] = "#{directory}:#{original}"
      yield
    end
  ensure
    ENV["PATH"] = original
  end
end
