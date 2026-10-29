# frozen_string_literal: true

module Hawk
  module Rails
    # Rails owns subscriber lifetime; each report resolves the current client.
    class ErrorSubscriber
      def self.install
        return if @installed

        ::Rails.error.subscribe(new)
        @installed = true
      end

      def report(error, handled:, severity:, context:, source: nil)
        client = Rails.integration_client(:rails_error)
        return unless client
        return if request_owned?(client, error, source)

        client.with_scope do |scope|
          scope.addons["rails_source"] = source
          client.report(error, mechanism: "rails.error", context: JSONValue.object(context),
                               level: severity, handled: handled)
        end
        nil
      rescue StandardError
        nil
      end

      private

      def request_owned?(client, error, source)
        return false unless source == "application.action_dispatch"

        client.current_scope.addons["boundary"] == "request" || client.consume_escape(error)
      end
    end
  end
end
