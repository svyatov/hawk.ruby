# frozen_string_literal: true

module Hawk
  # @api private
  module Rails
    # Rails deep filters and original-params blocks need each logical tree root.
    class PayloadFilter
      PATHS = [%w[context], %w[user], %w[data], %w[addons request params],
               %w[addons request body], %w[addons request headers], %w[addons job arguments]].freeze

      def initialize(filter)
        @filter = filter
      end

      def call(payload)
        fields = FilteredFields.new(payload, PATHS, containers_only: true)
        fields.restore(filter(payload)) { |key, value| filter_tree(key, value) }
      end

      private

      def filter(payload)
        JSONValue.object(@filter.filter(payload))
      end

      def filter_tree(key, value)
        case value
        when Hash then filter(value)
        when Array then value.map { |item| filter_tree(key, item) }
        else filter({ key => value })[key]
        end
      end
    end
  end
end
