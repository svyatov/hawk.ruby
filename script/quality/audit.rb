# frozen_string_literal: true

require "bundler/audit/scanner"
require "digest"
require "fileutils"
require "open3"
require "tmpdir"
require_relative "types"

module HawkQuality
  # Compare both revisions against one advisory snapshot.
  class Audit
    def initialize(root, database)
      @root = File.expand_path(root)
      @database = database
    end

    def self.refresh_database(root)
      path = File.join(root, ".superpowers/ruby-advisory-db")
      return Bundler::Audit::Database.download(path: path, quiet: true) unless File.directory?(path)

      database = Bundler::Audit::Database.new(path)
      raise Failure, "Advisory database refresh failed" unless database.update!(quiet: true)

      database
    end

    def findings
      lockfiles.flat_map do |lockfile|
        path = File.join(@root, lockfile)
        raise Failure, "Missing dependency lockfile: #{lockfile}" unless File.file?(path)

        Bundler::Audit::Scanner.new(@root, lockfile, @database).scan(ignore: []).map do |result|
          finding(lockfile, result)
        end
      end
    end

    def baseline(revision)
      raise Failure, "Base revision must be a full commit SHA" unless revision.match?(/\A[0-9a-f]{40}\z/)

      tree = git("ls-tree", "-r", "--name-only", revision, "--", "Gemfile", "Gemfile.lock", "gemfiles")
      Dir.mktmpdir("hawk-audit-base") do |directory|
        tree.lines(chomp: true).grep(%r{\A(?:Gemfile(?:\.lock)?|gemfiles/[^/]+\.gemfile(?:\.lock)?)\z}).each do |path|
          destination = File.join(directory, path)
          FileUtils.mkdir_p(File.dirname(destination))
          File.binwrite(destination, git("show", "#{revision}:#{path}"))
        end
        self.class.new(directory, @database).findings
      end
    end

    private

    def lockfiles
      expected = ["Gemfile", *Dir.glob("gemfiles/*.gemfile", base: @root)].map { |path| "#{path}.lock" }
      (expected + Dir.glob("gemfiles/*.gemfile.lock", base: @root)).uniq.sort
    end

    def finding(lockfile, result)
      if result.is_a?(Bundler::Audit::Results::UnpatchedGem)
        { lockfile: lockfile, type: "unpatched_gem", gem: result.gem.name,
          version: result.gem.version.to_s, advisory: result.advisory.id }
      else
        { lockfile: lockfile, type: "insecure_source", source_digest: Digest::SHA256.hexdigest(result.source.to_s) }
      end
    end

    def git(*)
      output, error, status = Open3.capture3("git", "-C", @root, *)
      raise Failure, "Cannot read audit baseline: #{error}" unless status.success?

      output
    end
  end
end
