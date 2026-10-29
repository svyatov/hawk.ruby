# frozen_string_literal: true

require "rake/testtask"

INTEGRATION_BUNDLES = {
  delayed_job: ["delayed_job", "test/hawk/delayed_job_test.rb"],
  resque: ["resque", "test/hawk/resque_test.rb"],
  sidekiq: ["sidekiq_8", "test/hawk/sidekiq_test.rb"],
  rack: ["rack_3", "test/hawk/rack_test.rb"],
  rails: ["rails_8_1", "test/hawk/rails/**/*_test.rb"]
}.freeze

Rake::TestTask.new(:test) do |task|
  task.libs << "lib" << "test"
  selection = ENV.delete("TEST")
  if selection
    task.pattern = selection
  else
    task.test_files = FileList["test/**/*_test.rb"].exclude(*INTEGRATION_BUNDLES.values.map(&:last))
  end
  task.warning = true
end

namespace :test do
  INTEGRATION_BUNDLES.each do |name, (bundle, pattern)|
    task name do
      gemfile = File.expand_path("gemfiles/#{bundle}.gemfile")
      sh({ "BUNDLE_GEMFILE" => gemfile, "BUNDLE_LOCKFILE" => "#{gemfile}.lock" },
         "bundle", "exec", "rake", "test", "TEST=#{pattern}")
    end
  end
  task active_job: :rails
end

namespace :check do
  task :lint do
    sh "bundle", "exec", "rubocop"
  end

  task :types do
    sh "bundle", "exec", "ruby", "script/check_types.rb"
  end

  task fast: %i[lint types test]
end

task default: "check:fast"
