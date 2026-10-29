# frozen_string_literal: true

require "test_helper"
require "support/collector"
require "support/subprocess"

class RakeIntegrationTest < HawkTest
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
