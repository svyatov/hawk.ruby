# frozen_string_literal: true

require "test_helper"
require "support/rails_capture"
require "support/subprocess"
require "active_support/testing/time_helpers"
require "delayed_job_active_record"
require "hawk/delayed_job"
require_relative "rails/active_job_test"

ActiveRecord::Schema.define do
  create_table :delayed_jobs, force: true do |table|
    table.integer :priority, default: 0, null: false
    table.integer :attempts, default: 0, null: false
    table.text :handler, null: false
    table.text :last_error
    table.datetime :run_at
    table.datetime :locked_at
    table.datetime :failed_at
    table.string :locked_by
    table.string :queue
    table.timestamps null: true
  end
end

class HawkDelayedPayload
  def perform
    raise "delayed job failed"
  end
end

class DelayedJobIntegrationTest < RailsCaptureTest
  include ActiveSupport::Testing::TimeHelpers

  def setup
    super
    Delayed::Job.delete_all
    Delayed::Worker.destroy_failed_jobs = false
    Delayed::Worker.max_attempts = 25
    Delayed::Worker.logger = Logger.new(File::NULL)
    @worker = Delayed::Worker.new
  end

  def test_delayed_job_reports_attempt_without_changing_reschedule
    travel_to(Time.utc(2026, 10, 29, 12)) do
      Hawk.client.configuration.integrations[:delayed_job] = false
      baseline = Delayed::Job.enqueue(HawkDelayedPayload.new)
      @worker.work_off(1)
      expected = baseline.reload.attributes.slice("attempts", "run_at", "failed_at")
      Hawk.client.configuration.integrations[:delayed_job] = true
      job = Delayed::Job.enqueue(HawkDelayedPayload.new)
      original_handler = job.handler
      @worker.work_off(1)

      assert_equal expected, job.reload.attributes.slice("attempts", "run_at", "failed_at")
      assert_equal original_handler, job.handler
      assert_equal 1, @collector.events.size
    end
  end

  def test_corrupt_handler_is_reported_and_retains_terminal_failure
    job = Delayed::Job.create!(handler: "--- !ruby/object:HawkMissingPayload {}\n", run_at: Time.current)
    @worker.work_off(1)

    refute_nil job.reload.failed_at
    assert_equal 1, @collector.events.size
    assert_equal "Delayed::DeserializationError", @collector.events.last.dig("payload", "type")
  end

  def test_terminal_failure_reports_once_across_error_and_failure_callbacks
    Delayed::Worker.max_attempts = 1
    job = Delayed::Job.enqueue(HawkDelayedPayload.new)
    @worker.work_off(1)

    refute_nil job.reload.failed_at
    assert_equal 1, @collector.events.size
  end

  def test_active_job_wrapper_restores_explicit_context
    ActiveJob::Base.queue_adapter = :delayed_job
    Hawk.set_context(section: "delayed-context")
    HawkFailingJob.perform_later
    @worker.work_off(1)

    assert_equal 1, @collector.events.size
    assert_equal "delayed-context", @collector.events.last.dig("payload", "context", "section")
  end

  def test_plugin_registration_keeps_initialized_lifecycle_and_existing_callbacks
    Hawk::DelayedJob.install
    assert_equal 1, Delayed::Worker.plugins.count(Hawk::DelayedJob::Plugin)
    Delayed::Job.enqueue(HawkDelayedPayload.new)
    @worker.work_off(1)

    assert_equal 1, @collector.events.size
  end

  def test_missing_client_preserves_job_execution_and_callback_registration
    Hawk.close
    job = Delayed::Job.enqueue(HawkDelayedPayload.new)
    assert_nil Hawk::DelayedJob::AROUND.call(nil, job)
    @worker.work_off(1)

    assert_equal 1, job.reload.attempts
    assert_empty @collector.events
  end

  def test_unsupported_delayed_job_major_is_not_registered
    program = <<~RUBY
      require "delayed_job"
      spec = Gem.loaded_specs.fetch("delayed_job").to_spec
      spec.version = "5.0.0"
      Gem.loaded_specs["delayed_job"] = spec
      require "hawk/delayed_job"
      print Delayed::Worker.plugins.include?(Hawk::DelayedJob::Plugin)
    RUBY
    output, error, status = Subprocess.run(program)

    assert status.success?, error
    assert_equal "false", output
  end
end
