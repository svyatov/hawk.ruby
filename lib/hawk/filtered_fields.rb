# frozen_string_literal: true

module Hawk
  # Empty placeholders retain parent/key masking while excluding saved contents.
  # @api private
  class FilteredFields
    def initialize(payload, paths, containers_only: false)
      @entries = []
      paths.each { |path| extract(payload, path, containers_only) }
    end

    def restore(payload)
      @entries.each do |path, key, value|
        parent = parent_at(payload, path)
        next unless parent

        case placeholder = parent[key]
        when Hash then parent[key] = yield(key, value) if placeholder.empty?
        end
      end
      payload
    end

    private

    def extract(payload, path, containers_only)
      key = path.fetch(-1)
      parent_path = path.take(path.size - 1)
      parent = parent_at(payload, parent_path)
      return unless parent&.key?(key)

      value = parent[key]
      return if containers_only && !container?(value)

      @entries << [parent_path, key, value]
      parent[key] = {}
    end

    def container?(value)
      case value
      when Hash, Array then true
      else false
      end
    end

    def parent_at(payload, path)
      current = payload
      path.each do |key|
        case child = current[key]
        when Hash then current = child
        else return nil
        end
      end
      current
    end
  end
end
