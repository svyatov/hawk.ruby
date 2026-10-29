# frozen_string_literal: true

require "test_helper"
require "support/rails_capture"
require "support/subprocess"
require "active_job"
require "action_cable"
require "action_cable/channel/test_case"

class HawkQuietJob < ActiveJob::Base
  discard_on RuntimeError

  def perform(*)
    raise "discarded fixture error"
  end
end

class HawkQuietChannel < ActionCable::Channel::Base
  attr_reader :handled

  rescue_from(RuntimeError) { |error| @handled = error }

  def ping
    raise "handled channel error"
  end
end

class HawkEdgeConnection < ActionCable::Connection::Base
  def connect
    raise "worker handoff"
  end
end

class RailsEdgeCasesTest < RailsCaptureTest
  class BrokenReport < Hawk::Client
    def report(*)
      raise IOError, "reporting failed"
    end
  end

  def test_rails_can_load_before_hawk_without_an_application
    program = <<~RUBY
      require "rails"
      require "action_controller/railtie"
      require "hawk"
      Hawk.init { |config| config.token = nil; config.global_errors = false }
      print defined?(Hawk::Railtie)
    RUBY
    output, error, status = Subprocess.run(program)

    assert status.success?, error
    assert_equal "constant", output
  end

  def test_disabled_integrations_preserve_framework_handling
    config = Hawk.client.configuration
    %i[rails rails_error action_cable active_job].each { |key| config.integrations[key] = false }
    config.breadcrumbs_rails = false
    Hawk::Rails.configure(config)
    Hawk::Rails.activate_integrations(config)
    run_framework_operations

    assert_empty @collector.events
  end

  def test_missing_client_preserves_framework_handling
    Hawk.close
    run_framework_operations

    assert_empty @collector.events
  end

  def test_child_switches_disable_hooks_while_the_master_rails_integration_stays_enabled
    %i[rails_error action_cable active_job].each { |key| Hawk.client.configuration.integrations[key] = false }
    run_framework_operations

    assert_empty @collector.events
    Hawk.capture_message("manual", context: { pin: "private" })
    assert_equal "[FILTERED]", @collector.events.last.dig("payload", "context", "pin")
  end

  def test_the_master_rails_switch_controls_previously_installed_hooks_after_reinitialization
    [false, true].each do |enabled|
      reinitialize_rails(enabled)
      before = @collector.events.size
      run_framework_operations(expect_context: enabled)
      ActiveSupport::Notifications.instrument("deliver.action_mailer", mail: "fixture")
      if enabled
        assert_equal before + 4, @collector.events.size
        refute_empty Hawk.client.current_scope.breadcrumbs
      else
        assert_empty Hawk.client.current_scope.breadcrumbs
        assert_equal before, @collector.events.size
      end
    end
  end

  def test_cable_worker_handler_does_not_repeat_an_escaping_error
    ActionCable.server.config.logger = Logger.new(File::NULL)
    connection = HawkEdgeConnection.new(ActionCable.server, Rack::MockRequest.env_for("/cable"))
    error = assert_raises(RuntimeError) { connection.send(:handle_open) }
    assert_nil connection.rescue_with_handler(error)

    assert_equal 1, @collector.events.size
  end

  def test_job_arguments_are_included_only_after_explicit_opt_in
    Hawk.client.configuration.include_job_arguments = true
    HawkQuietJob.perform_now("explicit-argument")

    assert_equal ["explicit-argument"], @collector.events.last.dig("payload", "addons", "job", "arguments")
  end

  def test_subscriber_failures_are_isolated_from_framework_callbacks
    previous = Hawk.client
    client = BrokenReport.new(previous.configuration, delivery: RecordingDelivery.new)
    Hawk.instance_variable_set(:@client, client)
    assert_nil Hawk::Rails::ErrorSubscriber.new.report(RuntimeError.new("original"), handled: true,
                                                                                     severity: :error, context: {})
  ensure
    previous&.close
  end

  def test_unsupported_rails_lanes_do_not_wrap_cable_or_jobs
    program = <<~RUBY
      require "rails"
      require "action_cable"
      require "active_job"
      def Rails.version; "9.0.0"; end
      require "hawk/rails"
      Hawk::Rails::ActionCable.install
      Hawk::Rails::ActiveJob.install
      print [ActionCable::Channel::Base.ancestors.include?(Hawk::Rails::ActionCable::ChannelMethods),
             ActiveJob::Base.ancestors.include?(Hawk::Rails::ActiveJob::InstanceMethods)].inspect
    RUBY
    output, error, status = Subprocess.run(program)

    assert status.success?, error
    assert_equal "[false, false]", output
  end

  private

  def reinitialize_rails(enabled)
    Hawk.init do |config|
      config.token = integration_token
      config.endpoint = @collector.url
      config.delivery_mode = :sync
      config.global_errors = false
      config.integrations[:rails] = enabled
    end
  end

  def run_framework_operations(expect_context: false)
    Rails.error.report(RuntimeError.new("explicit report"))
    assert_equal expect_context, HawkQuietJob.new.serialize.key?("hawk")
    HawkQuietJob.perform_now
    ActiveJob::Base.execute(HawkQuietJob.new.serialize)
    channel = HawkQuietChannel.new(ActionCable::Channel::ConnectionStub.new, "fixture")
    channel.perform_action("action" => "ping")
    assert_equal "handled channel error", channel.handled.message
  end
end
