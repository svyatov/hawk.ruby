# frozen_string_literal: true

module Hawk
  # Copies boundary data into a bounded JSON tree without custom serializers.
  # @api private
  class JSONValue
    def self.normalize(value)
      new.visit(value, 0)
    end

    def self.object(value)
      case result = normalize(value)
      when Hash then result
      else {}
      end
    end

    def initialize
      @seen = {}
      @seen.compare_by_identity
      @remaining = 5000
    end

    def visit(value, depth)
      @remaining -= 1
      return "[Truncated]" if depth > 10 || @remaining.negative?

      case value
      when String then text(value)
      when Array, Hash then container(value, depth)
      else scalar(value)
      end
    rescue StandardError
      "[Unavailable]"
    end

    private

    def scalar(value)
      case value
      when NilClass, TrueClass, FalseClass, Integer then value
      when Float then value.finite? ? value : nil
      when Object then "[#{value.class.name || 'Object'}]"
      else "[Unsupported]"
      end
    end

    def text(value)
      value.encode(Encoding::UTF_8, invalid: :replace, undef: :replace).byteslice(0, 8192).to_s.scrub("")
    end

    def container(value, depth)
      entered = false
      return "[Circular]" if @seen[value]

      @seen[value] = true
      entered = true
      case value
      when Array then value.take(100).map { |item| visit(item, depth + 1) }
      else mapping(value, depth)
      end
    ensure
      @seen.delete(value) if entered
    end

    def mapping(value, depth)
      # @type var result: payload
      result = {}
      value.first(100).each do |key, item|
        case key
        when String, Symbol
          result[text(key.to_s)] = visit(item, depth + 1)
        end
      end
      result
    end
  end
end
