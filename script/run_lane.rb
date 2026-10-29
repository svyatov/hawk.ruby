# frozen_string_literal: true

require_relative "test_lanes"

name = ARGV.fetch(0)
gemfile, pattern = HawkTestLanes::LANES.fetch(name)
path = File.expand_path("../#{gemfile}", __dir__)
environment = { "BUNDLE_GEMFILE" => path, "BUNDLE_LOCKFILE" => "#{path}.lock" }
arguments = %w[bundle exec rake test]
arguments << "TEST=#{pattern}" if pattern
exec environment, *arguments
