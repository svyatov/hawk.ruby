# frozen_string_literal: true

# One source of truth for local acceptance and the CI matrix.
module HawkTestLanes
  RUBIES = %w[3.3 3.4 4.0].freeze
  LANES = {
    "core" => ["Gemfile", nil],
    "rack-2" => ["gemfiles/rack_2.gemfile", "test/hawk/rack_test.rb"],
    "rack-3" => ["gemfiles/rack_3.gemfile", "test/hawk/rack_test.rb"],
    "rails-7.2" => ["gemfiles/rails_7_2.gemfile", "test/hawk/rails/**/*_test.rb"],
    "rails-8.0" => ["gemfiles/rails_8_0.gemfile", "test/hawk/rails/**/*_test.rb"],
    "rails-8.1" => ["gemfiles/rails_8_1.gemfile", "test/hawk/rails/**/*_test.rb"],
    "sidekiq-7-rails-7.2" => ["gemfiles/sidekiq_7_rails_7_2.gemfile", "test/hawk/sidekiq_test.rb"],
    "sidekiq-7" => ["gemfiles/sidekiq_7.gemfile", "test/hawk/sidekiq_test.rb"],
    "sidekiq-8" => ["gemfiles/sidekiq_8.gemfile", "test/hawk/sidekiq_test.rb"],
    "resque" => ["gemfiles/resque.gemfile", "test/hawk/resque_test.rb"],
    "delayed-job-7.2" => ["gemfiles/delayed_job_7_2.gemfile", "test/hawk/delayed_job_test.rb"],
    "delayed-job-8.0" => ["gemfiles/delayed_job_8_0.gemfile", "test/hawk/delayed_job_test.rb"],
    "delayed-job-8.1" => ["gemfiles/delayed_job.gemfile", "test/hawk/delayed_job_test.rb"]
  }.freeze

  def self.matrix
    RUBIES.flat_map do |ruby|
      LANES.map do |lane, (gemfile, _pattern)|
        { ruby: ruby, name: lane, lane: "#{ruby}-#{lane}", gemfile: gemfile }
      end
    end
  end
end

if $0 == __FILE__
  require "json"
  matrix = JSON.generate(include: HawkTestLanes.matrix)
  puts matrix
  output = ENV.fetch("GITHUB_OUTPUT", nil)
  File.open(output, "a") { |file| file.puts "matrix=#{matrix}" } if output
end
