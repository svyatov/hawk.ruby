# frozen_string_literal: true

require "test_helper"
require "support/rails_capture"
require "support/redis_server"
require "sidekiq"
require "sidekiq/processor"
require "sidekiq/fetch"
require "sidekiq/api"
require "hawk/sidekiq"
require_relative "rails/active_job_test"

class HawkSidekiqJob
  include Sidekiq::Job

  def perform(*)
    raise "sidekiq failed"
  end
end

class SidekiqIntegrationTest < RailsCaptureTest
  def setup
    super
    @redis = RedisServer.new
    @config = Sidekiq::Config.new
    @config.redis = { url: @redis.url }
    @config.logger = Logger.new(File::NULL)
    @config.error_handlers.clear
    Hawk::Sidekiq.register(@config)
    @capsule = @config.default_capsule
    @processor = Sidekiq::Processor.new(@capsule)
  end

  def teardown
    @config.redis_pool.shutdown(&:close)
    @redis.close
    super
  end

  def enqueue(klass = HawkSidekiqJob, arguments = ["original"])
    Sidekiq::Client.new(config: @config).push("class" => klass, "queue" => "critical", "args" => arguments)
    @config.redis { |redis| JSON.parse(redis.lpop("queue:critical")) }
  end

  def process(job)
    work = Sidekiq::BasicFetch::UnitOfWork.new("queue:critical", JSON.generate(job), @capsule)
    @processor.send(:process, work)
  end

  def test_failed_sidekiq_attempt_is_reported_once_and_native_retry_is_retained
    Hawk.set_context(section: "checkout")
    job = enqueue
    assert_equal ["original"], job.fetch("args")
    assert_equal "checkout", job.dig("hawk", "context", "section")
    assert_raises(RuntimeError) { process(job) }

    assert_equal 1, @collector.events.size
    assert_equal "critical", @collector.events.last.dig("payload", "addons", "job", "queue")
    retry_job = @config.redis { |redis| JSON.parse(redis.zrange("retry", 0, -1).last) }
    assert_equal 0, retry_job.fetch("retry_count")
    assert_raises(RuntimeError) { process(retry_job) }
    assert_equal 2, @collector.events.size
  end

  def test_active_job_wrapper_reports_one_failure
    data = HawkFailingJob.new.serialize
    wrapper = ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper
    assert_raises(RuntimeError) { process(enqueue(wrapper, [data])) }

    assert_equal 1, @collector.events.size
  end

  def test_failure_before_middleware_is_reported_by_backend_handler
    job = enqueue
    job["class"] = "HawkMissingSidekiqClass"
    assert_raises(NameError) { process(job) }

    assert_equal 1, @collector.events.size
  end

  def test_invalid_json_before_middleware_is_reported_without_payload_data
    work = Sidekiq::BasicFetch::UnitOfWork.new("queue:critical", "invalid-json", @capsule)
    @processor.send(:process, work)

    assert_equal 1, @collector.events.size
    refute @collector.events.last.dig("payload", "addons").key?("jobstr")
  end

  def test_registration_is_idempotent_and_disabled_capture_preserves_native_failure
    Hawk::Sidekiq.register(@config)
    Hawk.client.configuration.integrations[:sidekiq] = false
    assert_raises(RuntimeError) { process(enqueue) }

    assert_equal 1, @config.error_handlers.size
    assert_empty @collector.events
  end

  def test_malformed_job_context_does_not_inherit_the_enqueue_scope
    Hawk.set_context(section: "enqueue-only")
    job = enqueue
    job["hawk"] = { "version" => 2, "context" => { "section" => "untrusted" } }
    assert_raises(RuntimeError) { process(job) }

    assert_nil @collector.events.last.dig("payload", "context", "section")
    assert_equal "enqueue-only", Hawk.client.current_scope.context["section"]
  end
end
