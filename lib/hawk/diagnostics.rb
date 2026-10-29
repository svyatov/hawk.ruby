# frozen_string_literal: true

module Hawk
  # Counters and callbacks contain no event data or collector credentials.
  class Diagnostics
    # @api private
    def initialize(callback = nil, logger: nil)
      @callback = callback
      @logger = logger
      reset
    end

    # @api private
    def increment(name)
      reset if @pid != Process.pid
      @mutex.synchronize { @counts[name] = @counts.fetch(name, 0) + 1 }
      notify
      nil
    end

    # Returns a thread-safe copy of observed counters.
    #
    # Absent counters have not been incremented. Forked children start fresh counts.
    #
    # @return [Hash{Symbol => Integer}] counts such as :sent, :failed, :overflow,
    #   :filtered, and :duplicate_overflow
    def snapshot
      reset if @pid != Process.pid
      @mutex.synchronize { @counts.dup }
    end

    private

    def notify
      callback = @callback
      logger = @logger
      return unless callback || logger

      acquired = @mutex.synchronize { !@notifying && (@notifying = true) }
      return unless acquired

      emit
    ensure
      @mutex.synchronize { @notifying = false } if acquired
    end

    def emit
      Hook.call do
        @callback&.call(snapshot)
        @logger&.warn("Hawk delivery counters: #{JSON.generate(snapshot)}")
      end
    end

    def reset
      @pid = Process.pid
      @mutex = Mutex.new
      @counts = {}
      @notifying = false
    end
  end
end
