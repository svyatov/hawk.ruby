# frozen_string_literal: true

require_relative "../rack"
require "active_support/parameter_filter"
require_relative "payload_filter"
require_relative "error_subscriber"
require_relative "action_cable"
require_relative "active_job"
require_relative "../breadcrumbs/rails"

module Hawk
  # Framework filtering is injected without changing the user's before_send hook.
  module Rails
    def self.configure(configuration)
      return unless configuration.integration_enabled?(:rails)

      application = ::Rails.application
      return unless application

      filter = PayloadFilter.new(ActiveSupport::ParameterFilter.new(application.config.filter_parameters))
      configuration.framework_filter = ->(payload) { filter.call(payload) }
      activate_integrations(configuration)
      nil
    end

    def self.integration_client(integration)
      client = Hawk.client
      return unless client&.enabled? && client.configuration.integration_enabled?(:rails)

      client if client.configuration.integration_enabled?(integration)
    end

    def self.activate_integrations(configuration)
      ErrorSubscriber.install
      ActionCable.install
      ActiveJob.install
      Breadcrumbs::Rails.install if configuration.breadcrumbs_rails
      require_relative "../sidekiq" if defined?(::Sidekiq)
      require_relative "../resque" if defined?(::Resque)
      require_relative "../delayed_job" if defined?(::Delayed::Worker)
      nil
    end
  end

  # Rails constructs this middleware before its stack is frozen.
  class Railtie < ::Rails::Railtie
    initializer "hawk.middleware", after: :load_config_initializers do |application|
      application.middleware.insert_after(ActionDispatch::DebugExceptions, Hawk::Rack, integration: :rails)
    end
  end
end
