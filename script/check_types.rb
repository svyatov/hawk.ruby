# frozen_string_literal: true

require "csv"
require "open3"
require_relative "quality/types"

libraries = %w[base64 json uri open3 securerandom net-http timeout time logger]
arguments = libraries.flat_map { |library| ["-r", library] }
abort "RBS validation failed" unless system("bundle", "exec", "rbs", "-I", "sig", *arguments, "validate")

checked, diagnostics, checked_status = Open3.capture3("bundle", "exec", "steep", "check", "-j", "2")
$stdout.write(checked)
$stderr.write(diagnostics)
abort "Steep check failed" unless checked_status.success?
HawkQuality::Types.verify_output!(checked + diagnostics)

output, error, status = Open3.capture3("bundle", "exec", "steep", "stats", "--format=csv", "-j", "2")
abort error unless status.success?
HawkQuality::Types.verify_output!(error)

rows = CSV.parse(output, headers: true)
HawkQuality::Types.verify!(Dir.pwd, rows)
puts "Types: #{rows.size} files, zero untyped calls"
