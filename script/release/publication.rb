# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "open3"
require_relative "../../lib/hawk/version"

module HawkRelease
  class Failure < StandardError; end

  # Resume partial publication using the original, archived release bytes.
  class Publication
    def initialize(directory, tag:, commit:, repository:)
      @gem = File.join(directory, "hawk-ruby-#{Hawk::VERSION}.gem")
      @assets = [@gem, File.join(directory, "SHA256SUMS")]
      @tag = tag
      @commit = commit
      @repository = repository
    end

    def publish
      run!("gem", "push", @gem) unless registered?(lookup)
      release = github_release || create_release
      missing_assets(release).each { |path| run!("gh", "release", "upload", @tag, path, "--repo", @repository) }
      run!("gh", "release", "edit", @tag, "--draft=false", "--repo", @repository) if release.fetch("draft")
    end

    def registered?(response)
      return false if response.code == "404"
      raise Failure, "RubyGems version lookup failed: HTTP #{response.code}" unless response.code == "200"

      expected = Digest::SHA256.file(@gem).hexdigest
      unless JSON.parse(response.body)["sha"] == expected
        raise Failure, "Published gem checksum differs from the original build"
      end

      true
    end

    def missing_assets(release)
      verify_release!(release)
      existing = release.fetch("assets").to_h { |asset| [asset.fetch("name"), asset.fetch("digest")] }
      @assets.reject do |path|
        next false unless existing.key?(File.basename(path))

        expected = "sha256:#{Digest::SHA256.file(path).hexdigest}"
        unless existing.fetch(File.basename(path)) == expected
          raise Failure, "Existing GitHub asset checksum differs: #{path}"
        end

        true
      end
    end

    private

    def verify_release!(release)
      return if release.fetch("tag_name") == @tag && release.fetch("target_commitish") == @commit

      raise Failure, "Existing GitHub release tag or commit differs"
    end

    def lookup
      uri = URI("https://rubygems.org/api/v2/rubygems/hawk-ruby/versions/#{Hawk::VERSION}.json")
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 10) do |http|
        http.get(uri.request_uri)
      end
    end

    def github_release
      output, error, status = Open3.capture3("gh", "api", "repos/#{@repository}/releases/tags/#{@tag}")
      return JSON.parse(output) if status.success?
      return nil if error.include?("HTTP 404")

      raise Failure, "GitHub release lookup failed: #{error}"
    end

    def create_release
      run!("gh", "release", "create", @tag, "--verify-tag", "--target", @commit, "--title", @tag,
           "--draft", "--notes-file", "CHANGELOG.md", "--repo", @repository)
      github_release || raise(Failure, "Created GitHub release could not be read")
    end

    def run!(*)
      output, error, status = Open3.capture3(*)
      raise Failure, "Release command failed: #{output}#{error}" unless status.success?

      puts output
    end
  end
end
