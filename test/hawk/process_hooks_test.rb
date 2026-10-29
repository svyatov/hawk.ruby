# frozen_string_literal: true

require "test_helper"
require "support/collector"
require "support/subprocess"

class ProcessHooksTest < HawkTest
  def setup
    @collector = Collector.new
  end

  def teardown
    @collector.close
  end

  def test_uncaught_exception_preserves_exit_status_and_stderr
    program = initialized_program('raise "application failure"')
    _baseline_out, baseline_error, baseline_status = Subprocess.run(program, "HAWK_ENABLED" => "0")
    _output, error, status = Subprocess.run(program, "HAWK_ENABLED" => "1")

    assert_equal baseline_status.exitstatus, status.exitstatus
    assert_equal baseline_error, error
    assert_equal 1, @collector.events.size
    assert_equal "RuntimeError", @collector.events.first.dig("payload", "type")
    assert_equal "fatal", @collector.events.first.dig("payload", "addons", "level")
  end

  def test_handled_errors_and_normal_exit_are_not_reported
    program = initialized_program('begin; raise "handled"; rescue StandardError; end; exit 7')
    _output, _error, status = Subprocess.run(program, "HAWK_ENABLED" => "1")

    assert_equal 7, status.exitstatus
    assert_empty @collector.events
  end

  def test_interrupt_retains_signal_behavior
    program = initialized_program("raise Interrupt")
    _baseline_out, baseline_error, baseline_status = Subprocess.run(program, "HAWK_ENABLED" => "0")
    _output, error, status = Subprocess.run(program, "HAWK_ENABLED" => "1")

    assert_equal baseline_status.termsig, status.termsig
    assert_equal baseline_error, error
    assert_empty @collector.events
  end

  def test_capture_wrapper_and_shutdown_do_not_report_twice
    program = initialized_program('Hawk.capture { raise "failure" }')
    _output, _error, status = Subprocess.run(program, "HAWK_ENABLED" => "1")

    assert_equal 1, status.exitstatus
    assert_equal 1, @collector.events.size
  end

  def test_delivery_failure_does_not_replace_uncaught_error
    @collector.status = 429
    program = initialized_program('raise "original failure"')
    _baseline_out, baseline_error, baseline_status = Subprocess.run(program, "HAWK_ENABLED" => "0")
    _output, error, status = Subprocess.run(program, "HAWK_ENABLED" => "1")

    assert_equal baseline_status.exitstatus, status.exitstatus
    assert_equal baseline_error, error
  end

  def test_error_introspection_failure_does_not_replace_uncaught_error
    body = <<~RUBY
      class ApplicationError < StandardError
        def is_a?(_klass)
          raise "introspection failure"
        end
      end
      raise ApplicationError, "original failure"
    RUBY
    program = initialized_program(body)
    _baseline_out, baseline_error, baseline_status = Subprocess.run(program, "HAWK_ENABLED" => "0")
    _output, error, status = Subprocess.run(program, "HAWK_ENABLED" => "1")

    assert_equal baseline_status.exitstatus, status.exitstatus
    assert_equal baseline_error, error
    assert_equal 1, @collector.events.size
  end

  private

  def initialized_program(body)
    <<~RUBY
      require "hawk"
      if ENV["HAWK_ENABLED"] == "1"
        2.times do
          Hawk.init do |config|
            config.token = #{integration_token.inspect}
            config.endpoint = #{@collector.url.inspect}
          end
        end
      end
      #{body}
    RUBY
  end
end
