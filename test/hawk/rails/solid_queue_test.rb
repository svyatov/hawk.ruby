# frozen_string_literal: true

require "test_helper"
require "support/rails_capture"
require_relative "active_job_test"

ActiveRecord::Schema.verbose = false
load File.join(Gem.loaded_specs.fetch("solid_queue").full_gem_path,
               "lib/generators/solid_queue/install/templates/db/queue_schema.rb")

class RailsSolidQueueTest < RailsCaptureTest
  def test_real_claimed_jobs_report_failures_and_restore_context_between_jobs
    ActiveJob::Base.queue_adapter = :solid_queue
    ActiveJob::Base.logger = Logger.new(File::NULL)
    Hawk.set_context(section: "queued")
    previous_failures = SolidQueue::FailedExecution.count
    HawkFailingJob.perform_later("unchanged")
    Hawk.set_context(section: "next")
    HawkContextJob.perform_later
    claims = SolidQueue::ReadyExecution.claim("default", 2, 1)

    assert_equal 2, claims.size
    assert_raises(RuntimeError) { claims.first.perform }
    claims.last.perform

    assert_equal previous_failures + 1, SolidQueue::FailedExecution.count
    assert_equal 1, @collector.events.size
    assert_equal "queued", @collector.events.last.dig("payload", "context", "section")
    assert_equal "next", HawkContextJob.observed.context["section"]
    assert_equal "next", Hawk.client.current_scope.context["section"]
  end

  def test_real_claim_reports_unknown_job_class_during_deserialization
    ActiveJob::Base.queue_adapter = :solid_queue
    HawkContextJob.set(queue: "deserialize").perform_later
    record = SolidQueue::Job.last
    record.update!(arguments: record.arguments.merge("job_class" => "HawkMissingQueueJob"))
    claim = SolidQueue::ReadyExecution.claim("deserialize", 1, 1).first

    error = assert_raises(NameError) { claim.perform }
    assert_equal 1, @collector.events.size
    assert_equal error.class.name, @collector.events.last.dig("payload", "type")
  end
end
