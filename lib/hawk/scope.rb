# frozen_string_literal: true

require "securerandom"

module Hawk
  # Execution data is copied at scope boundaries and before event delivery.
  # Mutable execution data yielded by {Hawk.with_scope} and {Client#with_scope}.
  class Scope
    # Identity comparison avoids invoking application exception equality methods.
    # @api private
    class Ledger
      def initialize
        @errors = {}
        @errors.compare_by_identity
      end

      def accept(exception, evict: false)
        return :duplicate if @errors[exception]

        if @errors.size >= 256
          return :overflow unless evict

          @errors.shift
        end

        @errors[exception] = true
        :accepted
      end
    end

    # @return [Hash{String => Object}] copied context for this execution
    attr_reader :context

    # @return [Hash{String => Object}, nil] copied user data for this execution
    attr_reader :user

    # @return [String] fallback user identifier retained across copies of this scope
    attr_reader :anonymous_id
    # @api private
    attr_accessor :addons, :breadcrumbs, :ledger, :boundary, :request_metadata

    # @api private
    def initialize(context: {}, user: nil, anonymous_id: SecureRandom.uuid)
      @context = JSONValue.object(context)
      @user = user ? JSONValue.object(user) : nil
      @anonymous_id = anonymous_id
      @addons = {}
      @breadcrumbs = []
      @ledger = Ledger.new
      @boundary = false
      @request_metadata = nil
      @filtered_context_keys = {}
      @filtered_user = false
    end

    # Merges copied context, replacing matching top-level keys.
    #
    # @param context [Hash{String, Symbol => Object}] application context
    # @return [void]
    def set_context(context)
      update_context(context, false)
    end

    # Replaces the scoped user with copied data; nil clears it.
    #
    # @param user [Hash{String, Symbol => Object}, nil] user data
    # @return [void]
    def set_user(user)
      update_user(user, false)
    end

    # @api private
    def restore_filtered(context, user)
      update_context(context, true)
      update_user(user, true) if user
      nil
    end

    # @api private
    def filtered_paths(except_context: [], user_override: false)
      paths = (@filtered_context_keys.keys - except_context).map { |key| ["context", key] }
      paths << ["user"] if @filtered_user && !user_override
      paths << ["breadcrumbs"]
      paths
    end

    # @api private
    def event_addons
      reader = @request_metadata
      reader ? @addons.merge("request" => reader.call) : @addons
    end

    # @api private
    def event_data(context, user, default_user, addons)
      context = JSONValue.object(context)
      value = JSONValue.object(user || @user || default_user || {})
      value["id"] ||= @anonymous_id
      { context: @context.merge(context), user: value, breadcrumbs: @breadcrumbs, addons: event_addons.merge(addons),
        filtered_paths: filtered_paths(except_context: context.keys, user_override: !user.nil?) }
    end

    # @api private
    def copy
      duplicate = Scope.new(context: @context, user: @user, anonymous_id: @anonymous_id)
      duplicate.addons = JSONValue.object(@addons)
      duplicate.breadcrumbs = @breadcrumbs.map { |item| JSONValue.object(item) }
      duplicate.ledger = @ledger
      duplicate.boundary = @boundary
      duplicate.request_metadata = @request_metadata
      duplicate.restore_filtered(@context.slice(*@filtered_context_keys.keys), @filtered_user ? @user : nil)
      duplicate
    end

    private

    def update_context(context, filtered)
      values = JSONValue.object(context)
      values.each_key do |key|
        @filtered_context_keys.delete(key)
        @filtered_context_keys[key] = true if filtered
      end
      @context.merge!(values)
      nil
    end

    def update_user(user, filtered)
      @user = user ? JSONValue.object(user) : nil
      @filtered_user = filtered
      nil
    end
  end
end
