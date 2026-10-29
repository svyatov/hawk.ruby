# frozen_string_literal: true

require_relative "../hawk"
require "sidekiq"

module Hawk
  # Native middleware covers each backend attempt, including pre-execution errors.
  module Sidekiq
    def self.install
      return unless ::Sidekiq::VERSION.match?(/\A[78]\./)

      ::Sidekiq.configure_client { |config| register_client(config) }
      ::Sidekiq.configure_server { |config| register(config) }
    end

    def self.register_client(config)
      config.client_middleware { |chain| chain.add(ClientMiddleware) }
    end

    def self.register(config)
      register_client(config)
      config.server_middleware { |chain| chain.add(ServerMiddleware) }
      config.error_handlers << ERROR_HANDLER unless config.error_handlers.include?(ERROR_HANDLER)
    end

    def self.client
      client = Hawk.client
      client if client&.enabled? && client.configuration.integration_enabled?(:sidekiq)
    end

    def self.metadata(client, job)
      result = JSONValue.object(job.slice("class", "jid", "queue", "retry_count"))
      result["arguments"] = JSONValue.normalize(job["args"]) if client.configuration.include_job_arguments
      result
    end

    # Enqueue context uses Sidekiq's supported top-level metadata channel.
    class ClientMiddleware
      def call(_worker, job, _queue, _redis_pool = nil)
        client = Sidekiq.client
        context = JobContext.dump(client) if client
        job["hawk"] = context if context
        yield
      end
    end

    # Middleware delegates retries and acknowledgement to Sidekiq.
    class ServerMiddleware
      def call(_worker, job, _queue)
        client = Sidekiq.client
        return yield unless client

        Boundary.run(client, kind: :sidekiq, metadata: { "job" => Sidekiq.metadata(client, job) }) do
          JobContext.apply(client, job["hawk"])
          yield
        end
      end
    end

    # The execution marker is consumed only by this client's outer error handler.
    class ErrorHandler
      def call(error, context, _config = nil)
        client = Sidekiq.client
        return unless client
        return if client.consume_escape(error)

        job = JSONValue.object(context[:job])
        client.with_boundary(kind: :sidekiq, metadata: { "job" => Sidekiq.metadata(client, job) }) do
          JobContext.apply(client, job["hawk"])
          client.report(error, mechanism: "sidekiq.backend")
        end
        nil
      end
    end

    ERROR_HANDLER = ErrorHandler.new
  end
end

Hawk::Sidekiq.install
