# frozen_string_literal: true

module Hawk
  class Rack
    # Guards establish each foreign protocol before its type is narrowed.
    class Body
      def self.wrap(body, client:, scope:)
        if body.respond_to?(:each)
          if body.respond_to?(:to_path)
            file_body = body #: _RackFileBody
            return FileBody.new(file_body, client: client, scope: scope)
          end
          enumerable = body #: _RackEnumerableBody
          return new(enumerable, client: client, scope: scope)
        end
        if body.respond_to?(:call)
          callable = body #: _RackCallableBody
          return CallableBody.new(callable, client: client, scope: scope)
        end

        body
      end

      def initialize(body, client:, scope:)
        @body = body
        @client = client
        @scope = scope
      end

      def each(&block)
        return enum_for(:each) unless block_given?

        Boundary.resume(@client, @scope) { @body.each(&block) }
      end

      def close
        return unless @body.respond_to?(:close)

        body = @body #: _RackClosableBody
        Boundary.resume(@client, @scope) { body.close }
      end
    end

    # File responses retain the path API used by Rack sendfile middleware.
    class FileBody < Body
      def initialize(body, client:, scope:)
        super
        @file_body = body
      end

      def to_path
        Boundary.resume(@client, @scope) { @file_body.to_path }
      end
    end

    # Rack 3 can stream by calling a body with the server's stream object.
    class CallableBody
      def initialize(body, client:, scope:)
        @body = body
        @client = client
        @scope = scope
      end

      def call(stream)
        Boundary.resume(@client, @scope) { @body.call(stream) }
      end

      def close
        return unless @body.respond_to?(:close)

        body = @body #: _RackClosableBody
        Boundary.resume(@client, @scope) { body.close }
      end
    end
  end
end
