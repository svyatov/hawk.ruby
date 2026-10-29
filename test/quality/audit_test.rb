# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
require_relative "../../script/quality/audit"

class AuditTest < HawkTest
  def setup
    @directory = Dir.mktmpdir("hawk-audit")
    @root = File.join(@directory, "repo")
    @database = File.join(@directory, "advisories")
    FileUtils.mkdir_p([@root, File.join(@database, "gems/rack")])
    File.write(File.join(@database, "gems/rack/CVE-2026-9999.yml"), advisory)
    File.write(File.join(@root, "Gemfile"), "source 'https://rubygems.org'\n")
    git("init", "-q", "--initial-branch=main")
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_new_vulnerable_version_is_distinct_from_safe_base
    write_lock("2.0.0")
    base = commit
    write_lock("1.0.0")

    assert_equal 1, audit.findings.length
    assert_empty audit.baseline(base)
    assert_equal "CVE-2026-9999", audit.findings.first.fetch(:advisory)
  end

  def test_existing_vulnerability_does_not_become_new_when_advisories_refresh
    write_lock("1.0.0")
    base = commit

    assert_empty audit.findings - audit.baseline(base)
    assert_equal 1, audit.findings.length
  end

  def test_integration_bundle_cannot_escape_scanning
    write_lock("2.0.0")
    base = commit
    FileUtils.mkdir_p(File.join(@root, "gemfiles"))
    File.write(File.join(@root, "gemfiles/rack.gemfile"), "eval_gemfile '../Gemfile'\n")
    write_lock("1.0.0", "gemfiles/rack.gemfile.lock")

    introduced = audit.findings - audit.baseline(base)
    assert_equal(["gemfiles/rack.gemfile.lock"], introduced.map { |result| result.fetch(:lockfile) })
  end

  def test_missing_lockfile_and_invalid_base_fail_closed
    assert_raises(HawkQuality::Failure) { audit.findings }
    assert_raises(HawkQuality::Failure) { audit.baseline("--invalid") }
    assert_raises(HawkQuality::Failure) { audit.baseline("a" * 40) }
  end

  def test_ignore_configuration_cannot_hide_vulnerabilities
    write_lock("1.0.0")
    File.write(File.join(@root, ".bundler-audit.yml"), "ignore: [CVE-2026-9999]\n")

    assert_equal 1, audit.findings.length
  end

  def test_orphan_integration_lock_is_still_scanned
    write_lock("2.0.0")
    FileUtils.mkdir_p(File.join(@root, "gemfiles"))
    write_lock("1.0.0", "gemfiles/orphan.gemfile.lock")

    assert_equal 1, audit.findings.length
  end

  def test_baseline_manifest_is_not_executed
    File.write(File.join(@root, "Gemfile"), "raise 'Do not execute baseline code'\n")
    write_lock("2.0.0")

    assert_empty audit.baseline(commit)
  end

  def test_command_exit_statuses_distinguish_new_and_existing_findings
    write_lock("2.0.0")
    safe_base = commit
    write_lock("1.0.0")
    prepare_command

    refute command_status.success?
    assert command_status("--report-only").success?
    refute command_status("--base", safe_base).success?
    assert command_status("--base", commit).success?
  end

  def test_failed_database_refresh_cannot_pass_report_mode
    write_lock("2.0.0")
    prepare_command
    git("remote", "set-url", "origin", File.join(@directory, "missing"), directory: @command_database)

    refute command_status("--report-only").success?
  end

  private

  def audit
    HawkQuality::Audit.new(@root, Bundler::Audit::Database.new(@database))
  end

  def git(*, directory: @root)
    output, error, status = Open3.capture3("git", "-C", directory, *)
    raise error unless status.success?

    output.strip
  end

  def prepare_command
    %w[script/check_audit.rb script/quality/audit.rb script/quality/types.rb].each do |path|
      destination = File.join(@root, path)
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp(File.expand_path("../../#{path}", __dir__), destination)
    end
    prepare_command_database
  end

  def prepare_command_database
    @command_database = File.join(@root, ".superpowers/ruby-advisory-db")
    FileUtils.mkdir_p(File.dirname(@command_database))
    FileUtils.cp_r(@database, @command_database)
    git("init", "-q", "--initial-branch=master", directory: @command_database)
    git("add", "gems", directory: @command_database)
    git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.test", "-c", "commit.gpgsign=false",
        "commit", "-qm", "advisory", directory: @command_database)
    git("remote", "add", "origin", @command_database, directory: @command_database)
  end

  def command_status(*)
    _output, _error, status = Open3.capture3(RbConfig.ruby, File.join(@root, "script/check_audit.rb"), *)
    status
  end

  def commit
    git("add", "Gemfile", "Gemfile.lock")
    git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.test", "-c", "commit.gpgsign=false",
        "commit", "-qm", "fixture")
    git("rev-parse", "HEAD")
  end

  def write_lock(version, path = "Gemfile.lock")
    File.write(File.join(@root, path), <<~LOCK)
      GEM
        remote: https://rubygems.org/
        specs:
          rack (#{version})

      PLATFORMS
        ruby

      DEPENDENCIES
        rack
    LOCK
  end

  def advisory
    <<~YAML
      gem: rack
      cve: 2026-9999
      url: https://example.test/advisory
      title: Test fixture only
      date: 2026-01-01
      description: Test fixture only.
      patched_versions:
        - ">= 2.0.0"
    YAML
  end
end
