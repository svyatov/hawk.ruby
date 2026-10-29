# frozen_string_literal: true

module Hawk
  # Thread#[] stores values per fiber, including fibers sharing one thread.
  class ScopeStore
    def initialize(configuration, anonymous_id)
      @configuration = configuration
      @anonymous_id = anonymous_id
      @scope_key = "hawk.scope.#{anonymous_id}"
      @escape_key = "hawk.escape.#{anonymous_id}"
    end

    def current
      # @type var value: top
      value = Thread.current[@scope_key]
      case value
      when Scope then value
      else
        scope = Scope.new(context: @configuration.context, user: @configuration.user, anonymous_id: @anonymous_id)
        replace(scope)
        scope
      end
    end

    def replace(scope)
      Thread.current[@scope_key] = scope
      nil
    end

    def remember_escape(exception)
      Thread.current[@escape_key] = exception
      nil
    end

    def consume_escape(exception)
      # @type var value: top
      value = Thread.current[@escape_key]
      clear_escape
      case value
      when Exception then value.equal?(exception)
      else false
      end
    end

    def clear_escape
      Thread.current[@escape_key] = nil
      nil
    end

    def clear
      Thread.current[@scope_key] = nil
      clear_escape
    end
  end
end
