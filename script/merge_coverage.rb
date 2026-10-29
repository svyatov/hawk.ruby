# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"
require "simplecov"
require_relative "quality/coverage"

root = File.expand_path("..", __dir__)
run = ARGV.fetch(0) { abort "Usage: ruby script/merge_coverage.rb RUN [LANE ...]" }
abort "Invalid coverage run" unless run.match?(/\A[a-zA-Z0-9_-]+\z/) && ARGV.size > 1
paths = Dir[File.join(root, "coverage/runs", run, "**/manifest.json")]
abort "No coverage manifests" if paths.empty?
revision = Open3.capture2("git", "rev-parse", "HEAD", chdir: root).first.strip
sources = HawkQuality::Coverage.sources(root)
manifests = paths.map do |path|
  manifest = JSON.parse(File.read(path))
  HawkQuality::Coverage.verify_manifest!(manifest, revision: revision, sources: sources, run: run)
  manifest
end
HawkQuality::Coverage.verify_lanes!(manifests, ARGV.drop(1))

# Normalize remote checkout paths before SimpleCov merges branch identities.
reports = paths.map do |manifest_path|
  report_path = File.join(File.dirname(manifest_path), ".resultset.json")
  report = JSON.parse(File.read(report_path))
  report.each_value do |result|
    result["coverage"].transform_keys! do |path|
      File.join(root, HawkQuality::Coverage.relative_path(path))
    end
  end
  normalized = File.join(File.dirname(manifest_path), "normalized.json")
  File.write(normalized, JSON.generate(report))
  normalized
end
FileUtils.rm_f(File.join(root, "coverage/.resultset.json"))
SimpleCov.collate(reports, ignore_timeout: true) do
  root root
  coverage_dir File.join(root, "coverage")
  coverage :line
  coverage :branch
  cover "lib/**/*.rb"
end
result = SimpleCov.result
coverage = result.files.to_h { |file| [file.filename, file.coverage_data] }
HawkQuality::Coverage.verify_counts!(coverage, sources.keys)
receipt = { "revision" => revision, "sources" => sources, "run" => run,
            "report" => Digest::SHA256.file(File.join(root, "coverage/.resultset.json")).hexdigest }
File.write(File.join(root, "coverage/verified.json"), JSON.generate(receipt))
puts "Coverage: 100% lines and branches across #{manifests.size} reports"
