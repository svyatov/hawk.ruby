# frozen_string_literal: true

require "digest"
require_relative "types"

module HawkQuality
  # Only reports measured from identical sources and the requested run can merge.
  module Coverage
    def self.sources(root)
      Dir.glob("lib/**/*.rb", base: root).sort.to_h do |path|
        [path, Digest::SHA256.file(File.join(root, path)).hexdigest]
      end
    end

    def self.verify_manifest!(manifest, revision:, sources:, run:)
      valid = manifest["revision"] == revision && manifest["sources"] == sources && manifest["run"] == run
      raise Failure, "Stale or mismatched coverage manifest" unless valid

      manifest
    end

    def self.verify_lanes!(manifests, required)
      missing = required - manifests.map { |manifest| manifest.fetch("lane") }.uniq
      raise Failure, "Missing coverage lanes: #{missing.join(', ')}" unless missing.empty?

      manifests
    end

    def self.relative_path(path)
      path.sub(%r{\A.*?/lib/}, "lib/")
    end

    def self.verify_counts!(coverage, expected)
      normalized = coverage.transform_keys { |path| relative_path(path) }
      raise Failure, "Coverage omitted or added runtime files" unless normalized.keys.sort == expected.sort

      failures = normalized.flat_map { |path, data| uncovered(path, data) }
      raise Failure, "Coverage below 100%:\n#{failures.join("\n")}" unless failures.empty?

      coverage
    end

    def self.uncovered(path, data)
      lines = uncovered_lines(data)
      branches = data.fetch("branches").values.sum { |group| group.values.count(&:zero?) }
      return [] if lines.empty? && branches.zero?

      ["#{path}: lines #{lines.join(',')}; #{branches} uncovered branches"]
    end

    def self.uncovered_lines(data)
      data.fetch("lines").each_with_index.filter_map { |count, index| index + 1 if count&.zero? }
    end
  end
end
