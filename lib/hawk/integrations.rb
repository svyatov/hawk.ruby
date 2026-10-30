# frozen_string_literal: true

module Hawk
  # Discovers frameworks already loaded by the application during startup.
  # @api private
  module Integrations
    def self.load
      require_relative "rails/integration" if defined?(::Rails::Railtie)
      require_relative "sidekiq" if defined?(::Sidekiq)
      require_relative "resque" if defined?(::Resque)
      require_relative "delayed_job" if defined?(::Delayed::Worker)
      require_relative "rake" if defined?(::Rake::Task)
      nil
    end
  end
end
