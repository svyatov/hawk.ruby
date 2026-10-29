# frozen_string_literal: true

require "yard"
require_relative "quality/documentation"

abort "Documentation build failed" unless YARD::CLI::Yardoc.new.run("--no-save")
stats = YARD::CLI::Stats.new(false)
stats.parse_arguments
objects = stats.all_objects
problems = HawkQuality::Documentation.problems(objects)
abort problems.join("\n") unless problems.empty?

puts "Documentation: #{objects.size} public objects, complete parameter and return tags"
