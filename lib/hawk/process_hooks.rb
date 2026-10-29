# frozen_string_literal: true

module Hawk
  # Resolving the client at shutdown keeps repeated initialization idempotent.
  # @api private
  module ProcessHooks
    def self.install
      return if @installed

      @installed = true
      at_exit { report_exit($!) }
      nil
    end

    def self.report_exit(exception)
      client = Hawk.client
      return unless client
      return unless client.configuration.global_errors

      client.report(exception, mechanism: "at_exit", level: :fatal) if exception && !client.consume_escape(exception)
      client.close
      nil
    end
  end
end
