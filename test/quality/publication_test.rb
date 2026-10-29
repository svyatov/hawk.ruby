# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "digest"
require_relative "../../script/release/publication"

class PublicationTest < HawkTest
  def setup
    @directory = Dir.mktmpdir("hawk-publication")
    @gem = File.join(@directory, "hawk-ruby-#{Hawk::VERSION}.gem")
    File.write(@gem, "the original build")
    File.write(File.join(@directory, "SHA256SUMS"), "original checksums")
    File.write(File.join(@directory, "sbom.cdx.json"), "original inventory")
    @publication = HawkRelease::Publication.new(@directory, tag: "v#{Hawk::VERSION}", commit: "a" * 40,
                                                            repository: "svyatov/hawk.ruby")
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_missing_gem_requires_a_publish
    refute @publication.registered?(response("404"))
  end

  def test_matching_published_bytes_skip_another_gem_push
    assert @publication.registered?(response("200", "sha" => Digest::SHA256.file(@gem).hexdigest))
  end

  def test_changed_published_bytes_and_failed_lookups_stop_release
    assert_raises(HawkRelease::Failure) { @publication.registered?(response("200", "sha" => "different")) }
    assert_raises(HawkRelease::Failure) { @publication.registered?(response("503")) }
  end

  def test_a_partially_uploaded_release_resumes_only_missing_assets
    release = release_data
    release["assets"] << { "name" => File.basename(@gem), "digest" => "sha256:#{Digest::SHA256.file(@gem).hexdigest}" }

    assert_equal [File.join(@directory, "sbom.cdx.json"), File.join(@directory, "SHA256SUMS")],
                 @publication.missing_assets(release)
  end

  def test_a_different_tag_or_commit_cannot_be_resumed
    assert_raises(HawkRelease::Failure) { @publication.missing_assets(release_data.merge("tag_name" => "v9.9.9")) }
    assert_raises(HawkRelease::Failure) { @publication.missing_assets(release_data.merge("target_commitish" => "b" * 40)) }
  end

  def test_a_different_existing_asset_is_not_replaced
    release = release_data
    release["assets"] << { "name" => File.basename(@gem), "digest" => "sha256:different" }

    assert_raises(HawkRelease::Failure) { @publication.missing_assets(release) }
    release["assets"].first["digest"] = nil
    assert_raises(HawkRelease::Failure) { @publication.missing_assets(release) }
  end

  def test_lookup_finds_an_existing_draft_by_tag
    with_fake_github(release_data) do
      assert_equal release_data, @publication.send(:github_release)
    end
  end

  def test_gem_publication_requires_an_attestation_before_network_access
    assert_raises(HawkRelease::Failure) { @publication.publish_gem(attestation: File.join(@directory, "missing")) }
  end

  def test_gem_push_uses_the_supplied_attestation_and_original_artifact
    attestation = File.join(@directory, "bundle.json")
    File.write(attestation, "signed bundle")
    commands = []
    @publication.define_singleton_method(:lookup) { Struct.new(:code).new("404") }
    @publication.define_singleton_method(:run!) { |*command| commands << command }

    @publication.publish_gem(attestation: attestation)

    assert_equal [["gem", "push", @gem, "--attestation", attestation]], commands
  end

  def test_matching_registered_gem_is_not_pushed_again
    attestation = File.join(@directory, "bundle.json")
    File.write(attestation, "signed bundle")
    registered = response("200", "sha" => Digest::SHA256.file(@gem).hexdigest)
    @publication.define_singleton_method(:lookup) { registered }
    @publication.define_singleton_method(:run!) { |*| raise "Unexpected command" }

    @publication.publish_gem(attestation: attestation)
  end

  private

  def response(code, body = {})
    Struct.new(:code, :body).new(code, JSON.generate(body))
  end

  def release_data
    { "tag_name" => "v#{Hawk::VERSION}", "target_commitish" => "a" * 40, "draft" => true, "assets" => [] }
  end

  def with_fake_github(release)
    previous = ENV.to_h.slice("PATH", "HAWK_DRAFT_RESPONSE")
    path = File.join(@directory, "gh")
    File.write(path, fake_github)
    File.chmod(0o755, path)
    ENV["PATH"] = "#{@directory}:#{ENV.fetch('PATH')}"
    ENV["HAWK_DRAFT_RESPONSE"] = JSON.generate(release)
    yield
  ensure
    ENV["PATH"] = previous.fetch("PATH")
    ENV["HAWK_DRAFT_RESPONSE"] = previous["HAWK_DRAFT_RESPONSE"]
  end

  def fake_github
    <<~RUBY
      #!#{RbConfig.ruby}
      if ARGV.fetch(1).include?("/releases?")
        puts ENV.fetch("HAWK_DRAFT_RESPONSE")
      else
        warn "gh: Not Found (HTTP 404)"
        exit 1
      end
    RUBY
  end
end
