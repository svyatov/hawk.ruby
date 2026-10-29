# frozen_string_literal: true

module Hawk
  module Rails
    # Active Job owns retry decisions; Hawk observes escaping and terminal errors.
    module ActiveJob
      def self.install
        return if @installed || !::Rails.version.match?(/\A(?:7\.2|8\.[01])\./)

        ActiveSupport.on_load(:active_job) do
          ::ActiveJob::Base.singleton_class.prepend(ClassMethods)
          ::ActiveJob::Base.prepend(InstanceMethods)
          ::ActiveJob::Base.after_discard do |_job, error|
            Hawk::Rails::ActiveJob.client&.report(error, mechanism: "active_job.discard", handled: true)
          end
        end
        @installed = true
      end

      def self.client
        Rails.integration_client(:active_job)
      end

      def self.run(data, context, &block)
        client = self.client
        return yield unless client

        Boundary.run(client, kind: :active_job, metadata: { "job" => metadata(client, data) }) do
          JobContext.apply(client, context)
          block.call
        end
      end

      def self.metadata(client, data)
        result = JSONValue.object(data.slice("job_class", "job_id", "queue_name", "executions"))
        result["arguments"] = JSONValue.normalize(data["arguments"]) if client.configuration.include_job_arguments
        result
      end

      # Wrap deserialization failures as well as normal job execution.
      module ClassMethods
        def execute(job_data)
          ActiveJob.run(job_data, job_data["hawk"]) { super }
        end
      end

      # Serialization keeps application arguments and backend retry data intact.
      module InstanceMethods
        def serialize
          data = super
          client = ActiveJob.client
          context = JobContext.dump(client) if client
          data["hawk"] = context if context
          data
        end

        def deserialize(job_data)
          @hawk_context = JobContext.load(job_data["hawk"])
          super
        end

        def perform_now
          client = ActiveJob.client
          return super unless client

          data = { "job_class" => self.class.name, "job_id" => job_id, "queue_name" => queue_name,
                   "executions" => executions, "arguments" => arguments }
          context = @hawk_context || JobContext.dump(client)
          ActiveJob.run(data, context) { super }
        end
      end
    end
  end
end
