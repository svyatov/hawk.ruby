# frozen_string_literal: true

require "logger"

module Hawk
  # @api private
  module Breadcrumbs
    # Logger keeps control of level filtering and lazy block evaluation.
    module Logger
      LEVELS = %i[debug info warning error fatal unknown].freeze

      def self.install
        ::Logger.prepend(Methods) unless ::Logger.ancestors.include?(Methods)
      end

      def self.record(client, severity, message)
        normalized = Hawk::JSONValue.normalize(message)
        text = normalized.is_a?(String) ? normalized : JSON.generate(normalized)
        level = LEVELS.fetch(severity, :unknown)
        if client.configuration.breadcrumbs_logger
          client.add_breadcrumb(category: "logger", message: text,
                                level: level.to_s)
        end
        threshold = client.configuration.logger_error_level
        client.capture_message(text, level: level) if threshold && severity >= threshold
      rescue StandardError
        nil
      end

      def self.empty_message?(message)
        case message
        when nil then true
        else false
        end
      end

      def self.message(value, progname)
        empty_message?(value) ? progname : value
      end

      # Calls through Logger's public add entry point, including its log alias.
      module Methods
        def add(severity, message = nil, progname = nil, &block)
          client = Hawk::Breadcrumbs.client(:logger)
          severity ||= ::Logger::UNKNOWN
          return super unless client && severity >= level

          if block && Logger.empty_message?(message)
            # Explicit arguments avoid Steep 2.1's crash with a replacement block.
            super(severity, message, progname) do # rubocop:disable Style/SuperArguments
              value = block.call
              Logger.record(client, severity, value)
              value
            end
          else
            result = super
            Logger.record(client, severity, Logger.message(message, progname))
            result
          end
        end
        alias log add
      end
    end
  end
end
