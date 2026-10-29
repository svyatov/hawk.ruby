# frozen_string_literal: true

require_relative "../hawk"
require "resque"
require "resque/failure"

module Hawk
  # Resque 2.7 delegates failures to its existing backend without payload changes.
  # @api private
  module Resque
    def self.install
      return unless ::Resque::VERSION == "2.7.0"

      ::Resque::Job.prepend(JobMethods) unless ::Resque::Job.ancestors.include?(JobMethods)
      singleton = ::Resque::Failure.singleton_class
      singleton.prepend(FailureMethods) unless singleton.ancestors.include?(FailureMethods)
    end

    def self.client
      client = Hawk.client
      client if client&.enabled? && client.configuration.integration_enabled?(:resque)
    end

    def self.metadata(client, payload, queue)
      data = JSONValue.object(payload.slice("class"))
      data["queue"] = JSONValue.normalize(queue)
      data["arguments"] = JSONValue.normalize(payload["args"]) if client.configuration.include_job_arguments
      { "job" => data }
    end

    def self.run(payload, queue, &)
      # @type var client: Client?
      client = self.client
      return yield unless client

      Boundary.run(client, kind: :resque, metadata: metadata(client, payload, queue), &)
    ensure
      client&.flush
    end

    def self.report_failure(options)
      client = self.client
      return unless client

      case error = options[:exception]
      when Exception
        return if client.consume_escape(error)

        client.with_boundary(kind: :resque,
                             metadata: metadata(client, JSONValue.object(options[:payload]), options[:queue])) do
          client.report(error, mechanism: "resque.backend")
        end
      end
      nil
    rescue StandardError
      nil
    end

    # Flush every completed attempt because Resque may exit children with exit!.
    module JobMethods
      def perform
        Resque.run(payload, queue) { super }
      end
    end

    # Failures before perform still reach the configured Resque failure backend.
    module FailureMethods
      def create(options = {})
        Resque.report_failure(options)
        super
      ensure
        Resque.client&.flush
      end
    end
  end
end

Hawk::Resque.install
