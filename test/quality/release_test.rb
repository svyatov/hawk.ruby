# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"
require "rbconfig"

class ReleaseGuardTest < HawkTest
  SCRIPT = File.expand_path("../../script/verify_release.rb", __dir__)

  def test_accepts_the_version_tag_on_main
    with_repository do |directory|
      _output, error, status = verify(directory)

      assert status.success?, error
    end
  end

  def test_rejects_a_branch_trigger
    with_repository do |directory|
      _output, error, status = verify(directory, type: "branch")

      refute status.success?
      assert_includes error, "Release requires a tag"
    end
  end

  def test_rejects_a_different_version
    with_repository do |directory|
      _output, error, status = verify(directory, tag: "v9.9.9")

      refute status.success?
      assert_includes error, "Tag and gem version differ"
    end
  end

  def test_rejects_a_commit_outside_main
    with_repository do |directory|
      git(directory, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.test",
          "commit", "-qm", "unmerged", "--allow-empty")
      _output, error, status = verify(directory)

      refute status.success?
      assert_includes error, "Release commit must belong to main"
    end
  end

  private

  def with_repository
    Dir.mktmpdir("hawk-release") do |directory|
      git(directory, "init", "-q", "--initial-branch=main")
      git(directory, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.test",
          "commit", "-qm", "initial", "--allow-empty")
      git(directory, "update-ref", "refs/remotes/origin/main", "HEAD")
      yield directory
    end
  end

  def git(directory, *)
    output, error, status = Open3.capture3("git", "-C", directory, *)
    raise "Git fixture failed: #{output}#{error}" unless status.success?
  end

  def verify(directory, type: "tag", tag: "v#{Hawk::VERSION}")
    environment = { "GITHUB_REF_TYPE" => type, "GITHUB_REF_NAME" => tag }
    Open3.capture3(environment, RbConfig.ruby, SCRIPT, chdir: directory)
  end
end
