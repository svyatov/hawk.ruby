# frozen_string_literal: true

require "json"
require "optparse"
require_relative "quality/audit"

options = {}
OptionParser.new do |parser|
  parser.on("--base SHA") { |value| options[:base] = value }
  parser.on("--report-only") { options[:report_only] = true }
end.parse!
abort "Unexpected arguments" unless ARGV.empty?
abort "Choose --base or --report-only" if options[:base] && options[:report_only]

begin
  root = File.expand_path("..", __dir__)
  audit = HawkQuality::Audit.new(root, HawkQuality::Audit.refresh_database(root))
  findings = audit.findings
  actionable = options[:base] ? findings - audit.baseline(options[:base]) : findings
  puts JSON.pretty_generate(findings: findings, introduced: options[:base] ? actionable : nil)
  abort "Dependency audit found #{actionable.length} blocking findings" if !options[:report_only] && actionable.any?
rescue StandardError => e
  abort "Dependency audit failed: #{e.message}"
end
