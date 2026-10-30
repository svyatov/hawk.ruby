# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../script/release/publication"

class GitHubPublicationTest < HawkTest
  def setup
    @directory = Dir.mktmpdir("hawk-github-publication")
    @publication = HawkRelease::Publication.new(@directory, tag: "v#{Hawk::VERSION}", commit: "a" * 40,
                                                            repository: "svyatov/hawk.ruby")
    @delays = []
    delays = @delays
    @publication.define_singleton_method(:sleep) { |seconds| delays << seconds }
    @release = { "tag_name" => "v#{Hawk::VERSION}", "target_commitish" => "a" * 40,
                 "draft" => true, "assets" => [] }
    File.write(File.join(@directory, "gh"), fake_github)
    File.chmod(0o755, File.join(@directory, "gh"))
    @previous = ENV.to_h.slice("PATH", "HAWK_TEST_GITHUB")
    ENV["PATH"] = "#{@directory}:#{ENV.fetch('PATH')}"
    ENV["HAWK_TEST_GITHUB"] = @directory
  end

  def teardown
    @previous.each { |key, value| ENV[key] = value }
    ENV.delete("HAWK_TEST_GITHUB") unless @previous.key?("HAWK_TEST_GITHUB")
    FileUtils.remove_entry(@directory)
  end

  def test_delayed_draft_visibility_completes_without_creating_twice
    prepare(delay: 2)
    capture_io { @publication.publish_github }

    assert_equal [1, 2], @delays
    assert_equal(1, commands.count { |args| args.take(2) == %w[release create] })
    assert_equal(3, commands.count { |args| args.take(2) == %w[release upload] })
    assert_equal %w[release edit], commands.last.take(2)
    assert_includes commands.last, "--draft=false"
  end

  def test_immediately_visible_draft_does_not_wait
    prepare(delay: 0)
    capture_io { @publication.publish_github }

    assert_empty @delays
    assert_equal %w[release edit], commands.last.take(2)
  end

  def test_visibility_timeout_is_bounded_and_does_not_upload
    prepare(delay: 99)
    error = capture_failure

    assert_match(/Created GitHub release could not be read/, error.message)
    assert_equal [1, 2, 4, 8], @delays
    assert_equal 5, File.read(File.join(@directory, "reads")).to_i
    assert_equal(1, commands.count { |args| args.take(2) == %w[release create] })
    refute(commands.any? { |args| %w[upload edit].include?(args[1]) })
  end

  def test_lookup_errors_are_not_retried
    prepare(delay: 0)
    File.write(File.join(@directory, "lookup-error"), "")
    error = capture_failure

    assert_match(/GitHub release lookup failed: lookup denied/, error.message)
    assert_empty @delays
    refute(commands.any? { |args| %w[upload edit].include?(args[1]) })
  end

  def test_delayed_mismatched_release_is_never_published
    @release["target_commitish"] = "b" * 40
    prepare(delay: 1)
    error = capture_failure

    assert_equal "Existing GitHub release tag or commit differs", error.message
    assert_equal [1], @delays
    refute(commands.any? { |args| %w[upload edit].include?(args[1]) })
  end

  private

  def prepare(delay:)
    File.write(File.join(@directory, "delay"), delay.to_s)
    File.write(File.join(@directory, "release.json"), JSON.generate(@release))
  end

  def commands
    File.readlines(File.join(@directory, "commands")).map { |line| JSON.parse(line) }
  end

  def capture_failure
    error = nil
    capture_io { error = assert_raises(HawkRelease::Failure) { @publication.publish_github } }
    error
  end

  def fake_github
    <<~RUBY.sub("RUBY_EXECUTABLE", RbConfig.ruby)
      #!RUBY_EXECUTABLE
      require "json"
      directory = ENV.fetch("HAWK_TEST_GITHUB")
      File.open(File.join(directory, "commands"), "a") { |file| file.puts JSON.generate(ARGV) }
      created = File.join(directory, "created")
      if ARGV.first == "api" && File.exist?(created)
        if File.exist?(File.join(directory, "lookup-error"))
          warn "lookup denied"
          exit 1
        end
        counter = File.join(directory, "reads")
        reads = File.exist?(counter) ? File.read(counter).to_i + 1 : 1
        File.write(counter, reads.to_s)
        puts File.read(File.join(directory, "release.json")) if reads > File.read(File.join(directory, "delay")).to_i
      elsif ARGV.take(2) == %w[release create]
        File.write(created, "")
        puts "https://github.com/svyatov/hawk.ruby/releases/tag/draft"
      end
    RUBY
  end
end
