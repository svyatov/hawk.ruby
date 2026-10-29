# frozen_string_literal: true

module Hawk
  # User callbacks must not change application control flow or stop delivery.
  # @api private
  module Hook
    def self.call(&)
      Breadcrumbs.guard(:sdk, &)
    rescue Exception # rubocop:disable Lint/RescueException -- Isolate every exception raised by a user hook.
      nil
    end
  end
end
