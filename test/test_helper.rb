# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  coverage :line
  coverage :branch
  track_files "lib/**/*.rb"
end

require "minitest/autorun"
require "hawk"
