# frozen_string_literal: true

require "test_helper"
require "support/rails_capture"
require "support/redis_server"
require "support/subprocess"
require "resque"
require "resque/failure"
require "hawk/resque"
require_relative "rails/active_job_test"

class HawkResqueJob
  @queue = :critical

  def self.perform(*)
    raise "resque failed #{Process.pid}"
  end
end

class HawkResqueHookJob < HawkResqueJob
  def self.on_failure_fixture(_error, *)
    raise "failure callback failed"
  end
end

class ResqueIntegrationTest < RailsCaptureTest
  class BrokenOptions < Hash
    def [](_key)
      raise "options reader failed"
    end
  end

  def setup
    super
    @redis = RedisServer.new
    Resque.redis = @redis.url
    Resque.logger = Logger.new(File::NULL)
    @worker = Resque::Worker.new("critical")
  end

  def teardown
    Resque.redis.close
    @redis.close
    super
  end

  def reserve(klass = HawkResqueJob, *)
    Resque::Job.create("critical", klass, *)
    Resque::Job.reserve("critical")
  end

  def test_resque_child_flushes_one_report_and_parent_continues
    Hawk.client.configuration.delivery_mode = :async
    job = reserve(HawkResqueJob, "unchanged")
    Resque::Job.create("critical", HawkResqueJob, *job.args)
    @worker.work(0)

    assert_equal ["unchanged"], job.args
    assert_equal 1, Resque::Failure.count
    assert_equal 1, @collector.events.size
    refute_equal "resque failed #{Process.pid}", @collector.events.last.dig("payload", "title")
    assert Hawk.capture_message("parent continues")
    assert Hawk.flush
    assert_equal 2, @collector.events.size
  end

  def test_inline_worker_retains_failure_storage_and_reports_once
    job = reserve
    @worker.perform(job)

    assert_equal 1, Resque::Failure.count
    assert_equal 1, @collector.events.size
  end

  def test_unknown_class_and_failure_callbacks_are_reported
    job = reserve
    job.payload["class"] = "HawkMissingResqueJob"
    @worker.perform(job)
    @worker.perform(reserve(HawkResqueHookJob))

    assert_equal 2, Resque::Failure.count
    assert_equal 2, @collector.events.size
  end

  def test_active_job_metadata_is_carried_inside_its_arguments
    Hawk.set_context(section: "resque-context")
    data = HawkFailingJob.new.serialize
    wrapper = ActiveJob::QueueAdapters::ResqueAdapter::JobWrapper
    job = reserve(wrapper, data)
    @worker.perform(job)

    assert_equal [data], job.args
    assert_equal 1, @collector.events.size
    assert_equal "resque-context", @collector.events.last.dig("payload", "context", "section")
  end

  def test_failure_backend_can_report_without_a_perform_boundary
    Hawk.client.configuration.include_job_arguments = true
    options = { exception: RuntimeError.new("before perform"), worker: @worker, queue: "critical",
                payload: { "class" => "HawkResqueJob", "args" => ["explicit"] } }
    Resque::Failure.create(options)
    assert_equal 1, Resque::Failure.count
    assert_equal ["explicit"], @collector.events.last.dig("payload", "addons", "job", "arguments")
    assert_nil Hawk::Resque.report_failure({})
  end

  def test_missing_client_and_disabled_capture_retain_backend_failure_storage
    Hawk::Resque.install
    Hawk.client.configuration.integrations[:resque] = false
    @worker.perform(reserve)
    Hawk.close
    @worker.perform(reserve)

    assert_equal 2, Resque::Failure.count
    assert_empty @collector.events
  end

  def test_adapter_failure_does_not_replace_failure_backend_calls
    options = BrokenOptions.new.merge(exception: RuntimeError.new("original"), worker: @worker, queue: "critical",
                                      payload: { "class" => "HawkResqueJob", "args" => [] })
    Resque::Failure.create(options)

    assert_equal 1, Resque::Failure.count
    assert_empty @collector.events
  end

  def test_unsupported_resque_version_is_not_patched
    program = <<~RUBY
      require "resque"
      Resque.send(:remove_const, :VERSION)
      Resque.const_set(:VERSION, "3.0.0")
      require "hawk/resque"
      print Resque::Job.ancestors.include?(Hawk::Resque::JobMethods)
    RUBY
    output, error, status = Subprocess.run(program)

    assert status.success?, error
    assert_equal "false", output
  end
end
