# frozen_string_literal: true

module Hawk
  # Counters and callbacks contain no event data or collector credentials.
  class Diagnostics
    def initialize(callback = nil, logger: nil)
      @callback = callback
      @logger = logger
      reset
    end

    def increment(name)
      reset if @pid != Process.pid
      @mutex.synchronize { @counts[name] = @counts.fetch(name, 0) + 1 }
      notify
      nil
    rescue StandardError
      nil
    end

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

      Breadcrumbs.guard(:sdk) { emit }
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
