# frozen_string_literal: true

require_relative "../hawk"

module Hawk
  # Request scope covers application calls and the deferred response body.
  class Rack
    def initialize(app, client: nil, integration: :rack)
      @app = app
      @client = client
      @integration = integration
    end

    def call(env)
      client = active_client
      return @app.call(env) unless client

      Boundary.run(client, kind: :request, metadata: {}) do
        status, headers, body = invoke(client, env)
        [status, headers, Body.wrap(body, client: client, scope: client.current_scope.copy)]
      end
    end

    private

    def active_client
      client = @client || Hawk.client
      client if client&.enabled? && client.configuration.integration_enabled?(@integration)
    end

    def invoke(client, env)
      scope = client.current_scope
      scope.request_metadata = -> { metadata(env) }
      begin
        @app.call(env)
      ensure
        scope.request_metadata = nil
        scope.addons["request"] = metadata(env)
      end
    end

    def metadata(env)
      data = JSONValue.object(env.slice("REQUEST_METHOD", "PATH_INFO", "action_dispatch.request_id"))
      result = { "method" => data["REQUEST_METHOD"], "path" => data["PATH_INFO"],
                 "request_id" => data["action_dispatch.request_id"] }
      params = JSONValue.object(env["action_dispatch.request.parameters"] || env["rack.request.query_hash"])
      path = JSONValue.object(env["action_dispatch.request.path_parameters"])
      result.merge!("params" => params, "controller" => path["controller"], "action" => path["action"])
      optional_metadata(result, env)
    rescue StandardError
      {}
    end

    def optional_metadata(result, env)
      client = active_client
      return result unless client

      config = client.configuration
      result["headers"] = headers(env) if config.include_headers
      result["cookies"] = JSONValue.normalize(env["HTTP_COOKIE"]) if config.include_cookies
      result["body"] = JSONValue.normalize(env["RAW_POST_DATA"]) if config.include_request_body
      result
    end

    def headers(env)
      JSONValue.object(env.select { |key, _value| key.start_with?("HTTP_") && key != "HTTP_COOKIE" })
    end
  end
end

require_relative "rack/body"
