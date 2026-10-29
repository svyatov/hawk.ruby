# frozen_string_literal: true

module Hawk
  # Adapters share report ownership while retaining their own execution scopes.
  # @api private
  module Boundary
    def self.run(client, kind:, metadata:, inherit: false, &block)
      client.with_boundary(kind: kind, metadata: metadata, inherit: inherit) do
        protect(client, kind, &block)
      end
    end

    def self.resume(client, scope, &block)
      client.using_scope(scope) { protect(client, :request, &block) }
    end

    def self.protect(client, kind)
      yield
    rescue Exception => e # rubocop:disable Lint/RescueException -- Preserve original errors across execution boundaries.
      client.report(e, mechanism: kind.to_s)
      client.remember_escape(e)
      raise
    end

    private_class_method :protect
  end
end
