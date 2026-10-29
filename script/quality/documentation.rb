# frozen_string_literal: true

module HawkQuality
  # Checks the public objects selected by YARD's visibility and API filters.
  module Documentation
    def self.problems(objects)
      return ["No public API objects found"] if objects.empty?

      objects.flat_map do |object|
        issues = []
        issues << "missing documentation" if object.docstring.blank?
        issues.concat(method_problems(object)) if object.type == :method
        issues.map { |issue| "#{object.path}: #{issue}" }
      end
    end

    def self.method_problems(object)
      return return_problems(object) if object.is_attribute?

      names = parameter_names(object)
      tags = object.tags(:param)
      documented = tags.select { |tag| typed?(tag) }.map(&:name)
      issues = (names - documented).map { |name| "missing typed @param #{name}" }
      issues.concat(stale_parameters(tags, names))
      issues + return_problems(object)
    end

    def self.stale_parameters(tags, names)
      tags.reject { |tag| names.include?(tag.name) }
          .map { |tag| "@param #{tag.name} is not in the signature" }
    end

    def self.parameter_names(object)
      object.parameters.map { |name, _| name.sub(/\A[*&]+/, "").delete_suffix(":") }
            .reject { |name| name.empty? || name == "..." }
    end

    def self.typed?(tag)
      !Array(tag.types).empty?
    end

    def self.return_problems(object)
      return [] if object.name == :initialize || object.tags(:return).any? { |tag| typed?(tag) }

      ["missing typed @return"]
    end
  end
end
