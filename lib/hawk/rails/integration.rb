# frozen_string_literal: true

require_relative "../rack"
require "active_support/parameter_filter"

module Hawk
  # Framework filtering is injected without changing the user's before_send hook.
  module Rails
    def self.configure(configuration)
      return unless configuration.integration_enabled?(:rails)

      application = ::Rails.application
      return unless application

      filter = ActiveSupport::ParameterFilter.new(application.config.filter_parameters)
      configuration.framework_filter = ->(payload) { filter.filter(payload) }
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
