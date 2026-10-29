# frozen_string_literal: true

require "rbconfig"
require_relative "test_lanes"

run = ARGV.fetch(0) { abort "Usage: ruby script/merge_ci_coverage.rb RUN" }
lanes = HawkTestLanes.matrix.map { |entry| entry.fetch(:lane) }
exec RbConfig.ruby, File.expand_path("merge_coverage.rb", __dir__), run, *lanes
