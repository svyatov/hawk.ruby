# frozen_string_literal: true

require "bundler/setup"
require "json"

before = Thread.list.size
require "hawk"
loaded_threads = Thread.list.size - before

expected = ENV.fetch("HAWK_PACKAGE_ROOT")
actual = Gem.loaded_specs.fetch("hawk-ruby").full_gem_path
unless File.realpath(actual) == File.realpath(expected)
  raise "Loaded a different Hawk installation: #{actual}, expected #{expected}"
end

loaded = File.realpath(Hawk.method(:init).source_location.first)
raise "Loaded Hawk outside installed artifact" unless loaded.start_with?("#{File.realpath(expected)}/lib/")

Hawk.init do |config|
  config.token = Base64.strict_encode64(JSON.generate("integrationId" => "package-test", "secret" => "fixture"))
  config.endpoint = ENV.fetch("HAWK_PACKAGE_COLLECTOR")
  config.delivery_mode = :sync
  config.global_errors = false
  config.send_source = false
end
raise "Capture failed" unless Hawk.capture_message("installed artifact")
raise "Flush failed" unless Hawk.flush

frameworks = %i[Rails Rack Sidekiq Resque Delayed Rake].select { |name| Object.const_defined?(name) }
forbidden = Gem.loaded_specs.keys & %w[steep rbs rubocop minitest simplecov crap4ruby bundler-audit]
raise "Development tools loaded in core bundle" unless forbidden.empty?

report = { "version" => Hawk::VERSION, "frameworks" => frameworks, "new_threads" => loaded_threads }
Hawk.close
puts JSON.generate(report)
