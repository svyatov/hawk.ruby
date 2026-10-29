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

    assert_equal [File.join(@directory, "SHA256SUMS")], @publication.missing_assets(release)
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

  private

  def response(code, body = {})
    Struct.new(:code, :body).new(code, JSON.generate(body))
  end

  def release_data
    { "tag_name" => "v#{Hawk::VERSION}", "target_commitish" => "a" * 40, "draft" => true, "assets" => [] }
  end
end
