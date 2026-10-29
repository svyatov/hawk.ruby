# frozen_string_literal: true

module Hawk
  # Filters detached JSON data before hooks or transmission can observe it.
  class Filter
    SENSITIVE = /password|secret|passwd|api_?key|access_token|auth|credentials|mysql_pwd|stripetoken|card/i

    def initialize(configuration)
      @patterns = configuration.filter_parameters.map do |pattern|
        case pattern
        when String then Regexp.new(Regexp.escape(pattern), Regexp::IGNORECASE)
        else pattern
        end
      end
    end

    def call(value)
      filter(JSONValue.normalize(value))
    end

    private

    def filter(value)
      case value
      when Hash
        value.to_h { |key, item| [key, sensitive?(key) ? "[FILTERED]" : filter(item)] }
      when Array then value.map { |item| filter(item) }
      else value
      end
    end

    def sensitive?(key)
      SENSITIVE.match?(key) || @patterns.any? { |pattern| pattern.match?(key) }
    end
  end
end
