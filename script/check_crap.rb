# frozen_string_literal: true

require "json"
require "open3"
require_relative "quality/coverage"
require_relative "quality/crap"

root = File.expand_path("..", __dir__)
receipt = JSON.parse(File.read(File.join(root, "coverage/verified.json")))
revision = Open3.capture2("git", "rev-parse", "HEAD", chdir: root).first.strip
HawkQuality::Coverage.verify_manifest!(receipt, revision: revision, sources: HawkQuality::Coverage.sources(root),
                                                run: receipt.fetch("run"))
report = File.join(root, "coverage/.resultset.json")
unless receipt.fetch("report") == Digest::SHA256.file(report).hexdigest
  abort "Coverage report changed after verification"
end

output, error, status = Open3.capture3("bundle", "exec", "crap4ruby", "lib", "--coverage", report, "--threshold", "10")
$stdout.write(output)
$stderr.write(error)
abort "CRAP limit failed" unless status.success?
HawkQuality::Crap.verify_output!(output)
