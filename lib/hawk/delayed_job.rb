# frozen_string_literal: true

require_relative "../hawk"
require "delayed_job"
require "delayed/plugin"

module Hawk
  # Native lifecycle callbacks retain retries, payloads, and failure storage.
  module DelayedJob
    def self.install
      return unless supported_version?
      return if ::Delayed::Worker.plugins.include?(Plugin)

      # Initialize existing callbacks before attaching the new plugin once.
      ::Delayed::Worker.lifecycle
      ::Delayed::Worker.plugins << Plugin
      Plugin.new
    end

    def self.supported_version?
      specification = Gem.loaded_specs["delayed_job"]
      return false unless specification

      specification.version.to_s.start_with?("4.")
    end

    def self.client
      client = Hawk.client
      client if client&.enabled? && client.configuration.integration_enabled?(:delayed_job)
    end

    def self.run(job, &)
      client = self.client
      return yield unless client

      metadata = { "job" => { "backend" => "delayed_job", "id" => job.id,
                              "queue" => job.queue, "attempts" => job.attempts } }
      Boundary.run(client, kind: :delayed_job, metadata: metadata, &)
    end

    def self.report(job)
      client = self.client
      error = job.error
      client.report(error, mechanism: "delayed_job.backend") if client && error
      nil
    end

    AROUND = lambda do |_worker, job, &block|
      DelayedJob.run(job, &block) if block
    end

    # Worker rebuilds this callback set when a new worker is constructed.
    class Plugin < ::Delayed::Plugin
      callbacks do |lifecycle|
        lifecycle.around(:perform, &AROUND)
        lifecycle.after(:error) { |_worker, job| DelayedJob.report(job) }
        lifecycle.after(:failure) { |_worker, job| DelayedJob.report(job) }
      end
    end
  end
end

Hawk::DelayedJob.install
