# frozen_string_literal: true

require "securerandom"

module Hawk
  # Execution data is copied at scope boundaries and before event delivery.
  class Scope
    # Identity comparison avoids invoking application exception equality methods.
    class Ledger
      def initialize
        @errors = {}
        @errors.compare_by_identity
      end

      def accept(exception)
        return :duplicate if @errors[exception]
        return :overflow if @errors.size >= 256

        @errors[exception] = true
        :accepted
      end
    end

    attr_reader :context, :user, :anonymous_id
    attr_accessor :addons, :breadcrumbs, :ledger, :boundary, :request_metadata

    def initialize(context: {}, user: nil, anonymous_id: SecureRandom.uuid)
      @context = JSONValue.object(context)
      @user = user ? JSONValue.object(user) : nil
      @anonymous_id = anonymous_id
      @addons = {}
      @breadcrumbs = []
      @ledger = Ledger.new
      @boundary = false
      @request_metadata = nil
    end

    def set_context(context)
      @context.merge!(JSONValue.object(context))
      nil
    end

    def set_user(user)
      @user = user ? JSONValue.object(user) : nil
      nil
    end

    def event_addons
      reader = @request_metadata
      reader ? @addons.merge("request" => reader.call) : @addons
    end

    def copy
      duplicate = Scope.new(context: @context, user: @user, anonymous_id: @anonymous_id)
      duplicate.addons = JSONValue.object(@addons)
      duplicate.breadcrumbs = @breadcrumbs.map { |item| JSONValue.object(item) }
      duplicate.ledger = @ledger
      duplicate.boundary = @boundary
      duplicate.request_metadata = @request_metadata
      duplicate
    end
  end
end
