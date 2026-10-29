# frozen_string_literal: true

module Hawk
  module Breadcrumbs
    # Guard Net::HTTP's internal recursion while retaining the response block API.
    module NetHTTP
      def self.install
        ::Net::HTTP.prepend(Methods) unless ::Net::HTTP.ancestors.include?(Methods)
      end

      def self.record(client, request, host, status, started)
        path = request.path.split("?", 2).first.to_s
        path = URI.parse(path).path if path.start_with?("http://", "https://")
        data = { "method" => request.method, "host" => host, "path" => path, "status" => status,
                 "duration_ms" => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000 }
        client.add_breadcrumb(category: "http", message: "HTTP request", data: data)
      rescue StandardError
        nil
      end

      def self.connection_failed(client, host, started)
        data = { "method" => "CONNECT", "host" => host,
                 "duration_ms" => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000 }
        client.add_breadcrumb(category: "http", message: "HTTP connection failed", data: data)
      rescue StandardError
        nil
      end

      # The ensure path records failed operations without replacing their errors.
      module Methods
        def start(&block)
          # @type var client: Hawk::Client?
          client = Hawk::Breadcrumbs.client(:http)
          # @type var started: Float
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          yielded = false
          return super unless block && client

          super do |http|
            yielded = true
            block.call(http)
          end
        rescue StandardError
          NetHTTP.connection_failed(client, address, started) if client && !yielded
          raise
        end

        def request(request, body = nil, &)
          # @type var client: Hawk::Client?
          client = Hawk::Breadcrumbs.client(:http)
          return super unless client

          # @type var started: Float?
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          # @type var response: ::Net::HTTPResponse?
          response = Hawk::Breadcrumbs.guard(:http) { super }
        ensure
          NetHTTP.record(client, request, address, response&.code, started) if client && started
        end
      end
    end
  end
end
