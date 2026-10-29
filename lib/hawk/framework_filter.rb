# frozen_string_literal: true

module Hawk
  # Previously filtered fields cross later boundaries without another transform.
  # @api private
  module FrameworkFilter
    def self.call(configuration, payload, filtered_paths = [])
      filter = configuration.framework_filter
      return payload unless filter

      saved = FilteredFields.new(payload, filtered_paths)
      case result = Hook.call { filter.call(payload) }
      when Hash then saved.restore(JSONValue.object(result)) { |_key, value| value }
      end
    end
  end
end
