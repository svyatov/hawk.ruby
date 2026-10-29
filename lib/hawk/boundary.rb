# frozen_string_literal: true

module Hawk
  # Adapters share report ownership while retaining their own execution scopes.
  module Boundary
    def self.run(client, kind:, metadata:, inherit: false)
      client.with_boundary(kind: kind, metadata: metadata, inherit: inherit) do
        yield
      rescue Exception => e # rubocop:disable Lint/RescueException -- Preserve errors across framework boundaries.
        client.report(e, mechanism: kind.to_s)
        client.remember_escape(e)
        raise
      end
    end
  end
end
