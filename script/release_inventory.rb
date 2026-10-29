# frozen_string_literal: true

require_relative "release/inventory"

puts JSON.pretty_generate(HawkRelease::Inventory.new(ARGV.fetch(0)).document)
