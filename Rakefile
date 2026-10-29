# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |task|
  task.libs << "lib" << "test"
  selection = ENV.delete("TEST")
  if selection
    task.pattern = selection
  else
    task.test_files = FileList["test/**/*_test.rb"].exclude("test/hawk/rails/**/*", "test/hawk/rack_test.rb")
  end
  task.warning = true
end

namespace :test do
  task active_job: :rails
  task :rack do
    sh({ "BUNDLE_GEMFILE" => File.expand_path("gemfiles/rack_3.gemfile"),
         "BUNDLE_LOCKFILE" => File.expand_path("gemfiles/rack_3.gemfile.lock") },
       "bundle", "exec", "rake", "test", "TEST=test/hawk/rack_test.rb")
  end

  task :rails do
    sh({ "BUNDLE_GEMFILE" => File.expand_path("gemfiles/rails_8_1.gemfile"),
         "BUNDLE_LOCKFILE" => File.expand_path("gemfiles/rails_8_1.gemfile.lock") },
       "bundle", "exec", "rake", "test", "TEST=test/hawk/rails/**/*_test.rb")
  end
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
