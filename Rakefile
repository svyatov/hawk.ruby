# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |task|
  task.libs << "lib" << "test"
  task.pattern = ENV.delete("TEST") || "test/**/*_test.rb"
  task.warning = true
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
