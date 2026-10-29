# frozen_string_literal: true

require "securerandom"
require "fileutils"
require "rbconfig"
require_relative "test_lanes"

root = File.expand_path("..", __dir__)
run = ENV.fetch("HAWK_COVERAGE_RUN") { "local-#{SecureRandom.hex(8)}" }
prefix = RUBY_VERSION.split(".").take(2).join(".")
lanes = HawkTestLanes::LANES
FileUtils.mkdir_p(File.join(root, "coverage"))
File.write(File.join(root, "coverage/current-run"), run)
lanes.each do |lane, (gemfile, pattern)|
  path = File.join(root, gemfile)
  environment = { "BUNDLE_GEMFILE" => path, "BUNDLE_LOCKFILE" => "#{path}.lock",
                  "HAWK_COVERAGE_RUN" => run, "HAWK_COVERAGE_LANE" => "#{prefix}-#{lane}" }
  arguments = %w[bundle exec rake test]
  arguments << "TEST=#{pattern}" if pattern
  abort "Coverage suite failed: #{lane}" unless system(environment, *arguments, chdir: root)
end
exit if ARGV == ["--collect-only"]

abort "Coverage gate failed" unless system("bundle", "exec", RbConfig.ruby, "script/merge_coverage.rb", run,
                                           *lanes.keys.map { |lane| "#{prefix}-#{lane}" })
