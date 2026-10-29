# frozen_string_literal: true

module Hawk
  module Breadcrumbs
    # Notification payloads are intentionally excluded from automatic breadcrumbs.
    module Rails
      EVENTS = /\A(?:
        sql\.active_record|process_action\.action_controller|deliver\.action_mailer|
        (?:enqueue|enqueue_at|enqueue_retry|perform|perform_start|retry_stopped|discard)\.active_job
      )\z/x

      def self.install
        return if @installed

        ActiveSupport::Notifications.monotonic_subscribe(EVENTS) do |name, started, finished, _id, _payload|
          client = Hawk::Breadcrumbs.client(:rails)
          client&.add_breadcrumb(category: "rails", message: name,
                                 data: { "duration_ms" => (finished - started) * 1000 })
        end
        @installed = true
      end
    end
  end
end
