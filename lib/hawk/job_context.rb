# frozen_string_literal: true

module Hawk
  # Only explicit, filtered JSON context crosses a queue boundary.
  module JobContext
    def self.dump(client)
      return unless client.configuration.propagate_job_context

      scope = client.current_scope
      data = { "version" => 1, "context" => scope.context, "user" => scope.user }
      data = Filter.new(client.configuration).call(data)
      filter = client.configuration.framework_filter
      load(filter ? Hook.call { filter.call(JSONValue.object(data)) } : data)
    rescue StandardError
      nil
    end

    def self.load(raw)
      return unless valid?(raw, 0, { remaining: 1024 })

      data = JSONValue.object(raw)
      return unless valid_header?(data) && JSON.generate(data).bytesize <= 8192

      data.slice("version", "context", "user")
    rescue StandardError
      nil
    end

    def self.apply(client, raw)
      return unless client.configuration.propagate_job_context

      data = load(raw)
      return unless data

      client.set_context(JSONValue.object(data["context"]))
      client.set_user(JSONValue.object(data["user"])) if data["user"]
    end

    def self.valid_header?(data)
      case version = data["version"]
      when Integer then version == 1 && object?(data["context"]) && object?(data["user"], optional: true)
      else false
      end
    end

    def self.object?(value, optional: false)
      case value
      when Hash then true
      when nil then optional
      else false
      end
    end

    def self.valid?(value, depth, budget)
      budget[:remaining] = budget.fetch(:remaining) - 1
      return false if depth > 6 || budget.fetch(:remaining).negative?

      case value
      when Hash then valid_object?(value, depth, budget)
      when Array then valid_array?(value, depth, budget)
      when String then valid_key?(value)
      else valid_scalar?(value)
      end
    end

    def self.valid_scalar?(value)
      case value
      when Float then value.finite?
      when Integer, true, false, nil then true
      else false
      end
    end

    def self.valid_key?(value)
      case value
      when String then value.valid_encoding? && value.encoding.ascii_compatible? && value.bytesize <= 8192
      else false
      end
    end

    def self.valid_object?(value, depth, budget)
      value.size <= 100 && value.all? { |key, item| valid_key?(key) && valid?(item, depth + 1, budget) }
    end

    def self.valid_array?(value, depth, budget)
      value.size <= 100 && value.all? { |item| valid?(item, depth + 1, budget) }
    end
    private_class_method :valid?, :valid_header?, :object?, :valid_scalar?, :valid_key?, :valid_object?, :valid_array?
  end
end
