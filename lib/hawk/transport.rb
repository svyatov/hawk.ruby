# frozen_string_literal: true

require "net/http"
require "timeout"
require "time"

module Hawk
  # Every send performs at most one POST, with a bounded response and deadline.
  class Transport
    class ResponseTooLarge < StandardError; end

    def initialize(configuration)
      configuration.validate!
      @configuration = configuration
      uri = configuration.collector_uri if configuration.enabled?
      @uri = uri.is_a?(URI::HTTP) ? uri : nil
      reset
    end

    def available?
      reset if @pid != Process.pid
      @mutex.synchronize { !@uri.nil? && monotonic >= @cooldown_until }
    end

    def send(encoded)
      return :limited unless available?

      Timeout.timeout(5.0) { request(encoded) }
    rescue StandardError
      :failed
    end

    private

    def reset
      @mutex = Mutex.new
      @cooldown_until = 0.0
      @pid = Process.pid
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def connection(uri)
      http = Net::HTTP.new(uri.hostname.to_s, uri.port, nil)
      http.use_ssl = uri.is_a?(URI::HTTPS)
      http.open_timeout = @configuration.connect_timeout
      http.read_timeout = @configuration.read_timeout
      http.write_timeout = @configuration.write_timeout
      http.max_retries = 0
      http
    end

    def request(encoded)
      uri = @uri
      return :failed unless uri

      post = Net::HTTP::Post.new(uri.request_uri)
      post["Content-Type"] = "application/json"
      post.body = encoded
      result = :failed
      connection(uri).start do |http|
        http.request(post) { |response| result = handle(response) }
      end
      result
    end

    def handle(response)
      case response.code
      when "402", "429"
        cooldown(response["Retry-After"])
        :limited
      when "200"
        success?(response_body(response)) ? :accepted : :failed
      else :failed
      end
    end

    def response_body(response)
      content = +""
      response.read_body do |part|
        raise ResponseTooLarge, "Collector response exceeds limit" if content.bytesize + part.bytesize > 16_384

        content << part
      end
      content
    end

    def success?(content)
      # @type var data: top
      data = JSON.parse(content)
      case data
      when Hash then JSONValue.object(data).values_at("code", "error") == [200, false]
      else false
      end
    end

    def cooldown(header)
      delay = retry_delay(header)
      @mutex.synchronize { @cooldown_until = monotonic + delay.clamp(0.0, 300.0) }
    end

    def retry_delay(header)
      return @configuration.limit_cooldown unless header
      return header.to_f if /\A\d+\z/.match?(header)

      Time.httpdate(header) - Time.now
    rescue ArgumentError
      @configuration.limit_cooldown
    end
  end
end
