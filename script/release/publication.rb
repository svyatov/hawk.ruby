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
      @assets = [@gem, File.join(directory, "sbom.cdx.json"), File.join(directory, "SHA256SUMS")]
      @notes = File.join(directory, "release-notes.md")
      @tag = tag
      @commit = commit
      @repository = repository
    end

    def publish_gem(attestation:)
      raise Failure, "Missing gem attestation" unless File.file?(attestation)

      run!("gem", "push", @gem, "--attestation", attestation) unless registered?(lookup)
    end

    def publish_github
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
      query = ".[] | select(.tag_name == #{JSON.generate(@tag)})"
      output, error, status = Open3.capture3("gh", "api", "repos/#{@repository}/releases?per_page=100",
                                             "--paginate", "--jq", query)
      raise Failure, "GitHub release lookup failed: #{error}" unless status.success?

      JSON.parse(output) unless output.strip.empty?
    end

    def create_release
      run!("gh", "release", "create", @tag, "--verify-tag", "--target", @commit, "--title", @tag,
           "--draft", "--notes-file", @notes, "--repo", @repository)
      wait_for_created_release
    end

    def wait_for_created_release
      [0, 1, 2, 4, 8].each do |delay|
        sleep(delay) if delay.positive?
        release = github_release
        return release if release
      end
      raise Failure, "Created GitHub release could not be read after 5 attempts"
    end

    def run!(*)
      output, error, status = Open3.capture3(*)
      raise Failure, "Release command failed: #{output}#{error}" unless status.success?

      puts output
    end
  end
end
