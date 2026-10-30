# frozen_string_literal: true

require_relative "../hawk" unless defined?(Hawk.init)
require "rake"

module Hawk
  # Optional task capture delegates execution and preserves application errors.
  # @api private
  module Rake
    # Prepended to tasks without replacing their original execute implementation.
    module TaskMethods
      def execute(args = nil)
        client = Hawk.client
        return super unless client
        return super unless client.configuration.integration_enabled?(:rake)

        Boundary.run(client, kind: :rake, metadata: { "rake" => { "task" => name } }) { super }
      end
    end

    def self.install
      return unless ::Rake::VERSION.start_with?("13.")

      ::Rake::Task.prepend(TaskMethods) unless ::Rake::Task.ancestors.include?(TaskMethods)
      nil
    end
  end
end

Hawk::Rake.install
