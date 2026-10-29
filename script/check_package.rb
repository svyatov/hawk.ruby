# frozen_string_literal: true

require "bundler"
require "json"
require "tmpdir"
require "open3"
require "rbconfig"
require "rubygems/package"
require "digest"
require_relative "../test/support/collector"
require_relative "quality/package"

Dir.mktmpdir("hawk-package") do |directory|
  puts JSON.generate(HawkQuality::Package.new(directory).check)
end
