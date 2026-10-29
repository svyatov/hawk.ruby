# frozen_string_literal: true

require "test_helper"
require "support/rails_capture"
require "active_job"
require "active_job/queue_adapters/test_adapter"

class HawkFailingJob < ActiveJob::Base
  def perform(*)
    raise "job failed"
  end
end

class HawkDiscardJob < HawkFailingJob
  discard_on RuntimeError
end

class HawkRetryJob < HawkFailingJob
  retry_on RuntimeError, wait: 7, attempts: 2, jitter: 0
end

class HawkExhaustedJob < HawkFailingJob
  retry_on(RuntimeError, attempts: 1) { |_job, _error| :handled }
end

class HawkRescuedJob < HawkFailingJob
  rescue_from(RuntimeError) { :handled }
end

class HawkContextJob < ActiveJob::Base
  class_attribute :observed

  def perform(*)
    self.class.observed = Hawk.client.current_scope.copy
  end
end

class RailsActiveJobTest < RailsCaptureTest
  def setup
    super
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.logger = Logger.new(File::NULL)
  end

  def test_serialized_context_preserves_job_arguments
    Hawk.set_context(section: "checkout", password: "hidden")
    Hawk.set_user(id: "user-12")
    Hawk.client.current_scope.addons["request"] = { "path" => "/checkout" }
    job = HawkContextJob.new("original", 12)
    serialized = job.serialize

    assert_equal ["original", 12], serialized.fetch("arguments")
    assert_equal "checkout", serialized.dig("hawk", "context", "section")
    assert_equal "[FILTERED]", serialized.dig("hawk", "context", "password")
    ActiveJob::Base.execute(serialized)

    scope = HawkContextJob.observed
    assert_equal "checkout", scope.context["section"]
    assert_equal "user-12", scope.user["id"]
    assert_nil scope.addons["request"]
    assert_empty scope.breadcrumbs
  end

  def test_discard_exhaustion_and_escaping_failure_each_report_once
    HawkDiscardJob.perform_now
    HawkExhaustedJob.perform_now
    assert_raises(RuntimeError) { HawkFailingJob.perform_now }

    assert_equal 3, @collector.events.size
    assert_nil Hawk.client.current_scope.addons["job"]
  end

  def test_retry_schedule_is_preserved_and_intermediate_attempt_is_not_reported
    HawkRetryJob.perform_now("argument")
    queued = ActiveJob::Base.queue_adapter.enqueued_jobs.last

    assert_in_delta Time.now.to_f + 7, queued.fetch(:at), 1
    assert_equal ["argument"], queued.fetch("arguments")
    assert_empty @collector.events
    assert_raises(RuntimeError) { ActiveJob::Base.execute(queued) }
    assert_equal 1, @collector.events.size
  end

  def test_application_rescue_from_is_preserved
    HawkRescuedJob.perform_now

    assert_empty @collector.events
  end

  def test_unknown_job_class_is_reported_during_execute
    data = HawkContextJob.new.serialize.merge("job_class" => "HawkNonexistentJob")
    assert_raises(NameError) { ActiveJob::Base.execute(data) }

    assert_equal 1, @collector.events.size
  end

  def test_malformed_context_and_disabled_propagation_are_ignored
    data = HawkContextJob.new.serialize.merge("hawk" => { "version" => 2, "context" => { "evil" => true } })
    ActiveJob::Base.execute(data)

    assert_nil HawkContextJob.observed.context["evil"]
    Hawk.client.configuration.propagate_job_context = false
    Hawk.set_context(section: "private")
    refute HawkContextJob.new.serialize.key?("hawk")
  end

  def test_deleted_global_id_is_reported_without_changing_deserialization
    data = HawkContextJob.new.serialize
    data["arguments"] = [{ "_aj_globalid" => "gid://hawk/NonexistentModel/1" }]
    assert_raises(ActiveJob::DeserializationError) { ActiveJob::Base.execute(data) }

    assert_equal 1, @collector.events.size
  end
end
