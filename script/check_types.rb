# frozen_string_literal: true

require "csv"
require "open3"

checked, diagnostics, checked_status = Open3.capture3("bundle", "exec", "steep", "check", "-j", "2")
$stdout.write(checked)
$stderr.write(diagnostics)
failed = !checked_status.success? || (checked + diagnostics).match?(/FATAL:|Unexpected error:/)
abort "Steep check failed" if failed

output, error, status = Open3.capture3("bundle", "exec", "steep", "stats", "--format=csv", "-j", "2")
abort error unless status.success? && !error.match?(/FATAL:|Unexpected error:/)

rows = CSV.parse(output, headers: true)
expected = Dir["lib/**/*.rb"]
observed = rows.map { |row| row.fetch("File") }
abort "Type analysis omitted runtime files" unless (expected - observed).empty? && (observed - expected).empty?

invalid = rows.reject { |row| row["Status"] == "success" && Integer(row.fetch("Untyped calls")).zero? }
abort "Untyped calls or failed type analysis: #{invalid.map { |row| row['File'] }.join(', ')}" unless invalid.empty?

puts "Types: #{expected.size} files, zero untyped calls"
