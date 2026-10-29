# frozen_string_literal: true

require "test_helper"
require "support/collector"
require "support/subprocess"

class RakeIntegrationTest < HawkTest
  def test_unsupported_rake_major_is_not_patched
    program = <<~RUBY
      require "rake"
      Rake.send(:remove_const, :VERSION)
      Rake.const_set(:VERSION, "14.0.0")
      require "hawk/rake"
      print Rake::Task.ancestors.include?(Hawk::Rake::TaskMethods)
    RUBY
    output, error, status = Subprocess.run(program)

    assert status.success?, error
    assert_equal "false", output
  end

  def test_inactive_task_capture_keeps_normal_execution
    program = <<~RUBY
      require "hawk/rake"
      Rake::Task.define_task("plain") { print "plain" }
      Rake::Task["plain"].invoke
      Hawk.init { |config| config.token = nil; config.integrations[:rake] = false }
      Rake::Task.define_task("disabled") { print "disabled" }
      Rake::Task["disabled"].invoke
    RUBY
    output, error, status = Subprocess.run(program)

    assert status.success?, error
    assert_equal "plaindisabled", output
  end

  def test_rake_failure_keeps_original_exception_and_reports_once
    collector = Collector.new
    program = <<~RUBY
      require "hawk/rake"
      Hawk::Rake.install
      Hawk.init do |config|
        config.token = #{integration_token.inspect}
        config.endpoint = #{collector.url.inspect}
      end
      Rake::Task.define_task("failure") { raise "task failed" }
      Rake::Task["failure"].invoke
    RUBY
    _output, error, status = Subprocess.run(program)

    assert_equal 1, status.exitstatus
    assert_includes error, "task failed (RuntimeError)"
    assert_equal 1, collector.events.size
    assert_equal "failure", collector.events.first.dig("payload", "addons", "rake", "task")
  ensure
    collector&.close
  end
end
