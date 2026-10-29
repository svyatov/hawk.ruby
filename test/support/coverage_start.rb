# frozen_string_literal: true

require "simplecov"
require "json"
require "securerandom"
require "open3"
require "fileutils"
require_relative "../../script/quality/coverage"

# This bootstrap is test-only and runs before any SDK file is loaded.
module HawkCoverage
  ROOT = File.expand_path("../..", __dir__)
  RUN = ENV.fetch("HAWK_COVERAGE_RUN", "local")
  LANE = ENV.fetch("HAWK_COVERAGE_LANE", "core-#{RUBY_VERSION}")
  DIRECTORY = File.join(ROOT, "coverage/runs", RUN, LANE, SecureRandom.hex(8))
  MANIFEST = {
    "run" => RUN, "lane" => LANE,
    "revision" => Open3.capture2("git", "rev-parse", "HEAD", chdir: ROOT).first.strip,
    "sources" => HawkQuality::Coverage.sources(ROOT)
  }.freeze

  # Resque and some fork tests use exit!, which bypasses Ruby's exit callbacks.
  module ExitCoverage
    def exit!(status = 1)
      SimpleCov.at_exit.call
      super
    end
  end
end

SimpleCov.root(HawkCoverage::ROOT)
SimpleCov.coverage_dir(HawkCoverage::DIRECTORY)
SimpleCov.command_name("#{HawkCoverage::LANE}-#{Process.pid}")
SimpleCov.start do
  coverage :line
  coverage :branch
  cover "lib/**/*.rb"
  merge_subprocesses true
  formatter SimpleCov::Formatter::SimpleFormatter
end
SimpleCov.at_exit do
  SimpleCov.result.format!
  FileUtils.mkdir_p(HawkCoverage::DIRECTORY)
  File.write(File.join(HawkCoverage::DIRECTORY, "manifest.json"), JSON.generate(HawkCoverage::MANIFEST))
end
Kernel.prepend(HawkCoverage::ExitCoverage)
Process.singleton_class.prepend(HawkCoverage::ExitCoverage)
