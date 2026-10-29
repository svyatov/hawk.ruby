# frozen_string_literal: true

module Hawk
  module Rails
    # These wrappers match Rails 7.2, 8.0, and 8.1 lifecycle methods.
    module ActionCable
      def self.install
        return if @installed || !::Rails.version.match?(/\A(?:7\.2|8\.[01])\./)

        ActiveSupport.on_load(:action_cable_channel) do |base|
          base.prepend(ChannelMethods)
          base.prepend(RescueMethods)
        end
        ActiveSupport.on_load(:action_cable_connection) do |base|
          base.prepend(ConnectionMethods)
          base.prepend(RescueMethods)
        end
        @installed = true
      end

      def self.client
        client = Hawk.client
        client if client&.enabled? && client.configuration.integration_enabled?(:action_cable)
      end

      def self.run(owner, operation, &)
        client = self.client
        return yield unless client

        metadata = { "cable" => { "class" => owner.class.name, "operation" => operation } }
        Boundary.run(client, kind: :cable, metadata: metadata, &)
      end

      def self.report(error, handled:)
        client = self.client
        return unless client
        return if client.consume_escape(error)

        client.report(error, mechanism: "action_cable", handled: handled)
      end

      # Channel entry points establish per-operation scopes.
      module ChannelMethods
        def perform_action(data)
          ActionCable.run(self, "perform_action") { super }
        end

        def subscribe_to_channel
          ActionCable.run(self, "subscribe_to_channel") { super }
        end

        def unsubscribe_from_channel
          ActionCable.run(self, "unsubscribe_from_channel") { super }
        end
      end

      # Connection lifecycle callbacks run on reusable Cable workers.
      module ConnectionMethods
        private

        def handle_open
          ActionCable.run(self, "handle_open") { super }
        end

        def handle_close
          ActionCable.run(self, "handle_close") { super }
        end
      end

      # Observe consumed errors without replacing application rescue handlers.
      module RescueMethods
        def rescue_with_handler(exception)
          result = super
          ActionCable.report(exception, handled: !result.nil?)
          result
        end
      end
    end
  end
end
