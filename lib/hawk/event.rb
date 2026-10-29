# frozen_string_literal: true

module Hawk
  # Builds the native protocol payload; hooks never receive integration tokens.
  class Event
    def initialize(configuration:, id:, exception: nil, message: nil, context: {}, user: nil,
                   breadcrumbs: [], addons: {}, level: :error)
      @configuration = configuration
      @addons = metadata(id, level).merge(JSONValue.object(addons))
      @payload = {
        "title" => exception ? title(exception) : (message || "Message"),
        "type" => exception ? exception.class.name.to_s : "Message",
        "catcherVersion" => VERSION,
        "context" => JSONValue.normalize(context),
        "breadcrumbs" => JSONValue.normalize(breadcrumbs),
        "addons" => @addons
      }
      @payload["user"] = JSONValue.normalize(user) if user
      @payload["release"] = configuration.release if configuration.release
      attach_exception(exception) if exception
    end

    def encode
      payload = filtered_payload
      return unless payload

      hook = @configuration.before_send
      if hook
        case result = hook.call(payload)
        when Hash then payload = JSONValue.object(result)
        else return nil
        end
      end
      return unless valid_payload?(payload)

      bounded_envelope(payload)
    rescue StandardError
      nil
    end

    private

    def filtered_payload
      payload = JSONValue.object(Filter.new(@configuration).call(@payload))
      filter = @configuration.framework_filter
      return payload unless filter

      case result = filter.call(payload)
      when Hash then JSONValue.object(result)
      end
    end

    def title(exception)
      JSONValue.normalize(exception.message).to_s
    rescue StandardError
      exception.class.name.to_s
    end

    def metadata(id, level)
      { "event_id" => id, "level" => level.to_s, "environment" => @configuration.environment,
        "ruby" => { "version" => RUBY_VERSION, "platform" => RUBY_PLATFORM, "engine" => RUBY_ENGINE } }
    end

    def attach_exception(exception)
      @payload["backtrace"] = Source.new(@configuration).frames(exception)
      chain = causes(exception)
      @addons["causes"] = chain unless chain.empty?
    end

    def causes(exception)
      # @type var result: Array[payload]
      result = []
      # @type var seen: Hash[Exception, bool]
      seen = {}
      seen.compare_by_identity
      current = exception.cause
      while current && result.size < 10 && !seen[current]
        seen[current] = true
        result << { "type" => current.class.name.to_s, "title" => title(current),
                    "backtrace" => Source.new(@configuration).frames(current) }
        current = current.cause
      end
      result
    rescue StandardError
      result
    end

    def valid_payload?(payload)
      case value = payload["title"]
      when String then !value.empty?
      else false
      end
    end

    def envelope(payload)
      JSON.generate("token" => @configuration.token, "catcherType" => "errors/ruby", "payload" => payload)
    end

    def bounded_envelope(payload)
      %i[sources breadcrumbs causes context addons frames].each do |phase|
        encoded = envelope(payload)
        return encoded if encoded.bytesize <= 262_144

        trim(payload, phase)
      end
      encoded = envelope(payload)
      encoded if encoded.bytesize <= 262_144
    end

    def trim(payload, phase)
      case phase
      when :sources then trim_sources(payload)
      when :breadcrumbs then keep_first(payload, "breadcrumbs", newest: true)
      when :causes
        case addons = payload["addons"]
        when Hash then keep_first(addons, "causes")
        end
      when :context, :addons then payload.delete(phase.to_s)
      else keep_first(payload, "backtrace")
      end
    end

    def trim_sources(payload)
      case frames = payload["backtrace"]
      when Array
        frames.each do |frame|
          case frame
          when Hash then frame.delete("sourceCode")
          end
        end
      end
    end

    def keep_first(payload, key, newest: false)
      case items = payload[key]
      when Array then payload[key] = newest ? items.last(1) : items.take(1)
      end
    end
  end
end
