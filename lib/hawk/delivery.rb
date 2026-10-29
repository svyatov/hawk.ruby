# frozen_string_literal: true

module Hawk
  # Queue capacity never blocks capture; flush and close have explicit deadlines.
  # @api private
  class Delivery
    def initialize(configuration, transport:, diagnostics:)
      @configuration = configuration
      @transport = transport
      @diagnostics = diagnostics
      @closed = false
      reset
    end

    def enqueue(_identifier, encoded)
      reset if @pid != Process.pid
      return false unless @transport.available?

      snapshot = encoded.dup.freeze
      accepted = @mutex.synchronize { accept(snapshot) }
      unless accepted
        @diagnostics.increment(:overflow) unless @closed
        return false
      end
      deliver(snapshot) if @configuration.delivery_mode == :sync
      true
    end

    def flush(timeout:)
      reset if @pid != Process.pid
      return false unless timeout.finite? && timeout >= 0
      return false if Thread.current.equal?(@worker)

      deadline = monotonic + timeout
      @mutex.synchronize do
        while @pending.positive?
          remaining = deadline - monotonic
          return false unless remaining.positive?

          @condition.wait(@mutex, remaining)
        end
      end
      true
    end

    def close(timeout:)
      reset if @pid != Process.pid
      deadline = monotonic + timeout
      @mutex.synchronize do
        @closed = true
        @condition.broadcast
      end
      return false unless flush(timeout: timeout)

      worker = @worker
      worker.nil? || !worker.join([deadline - monotonic, 0.0].max).nil?
    end

    private

    def reset
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @queue = []
      @pending = 0
      @worker = nil
      @pid = Process.pid
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def accept(encoded)
      return false if @closed
      return false if @queue.size >= @configuration.queue_capacity

      @pending += 1
      if @configuration.delivery_mode == :async
        @queue << encoded
        worker = @worker || Thread.new { work }
        worker.report_on_exception = false
        @worker = worker
        @condition.signal
      end
      true
    end

    def next_event
      @mutex.synchronize do
        @condition.wait(@mutex) while @queue.empty? && !@closed
        @queue.shift
      end
    end

    def work
      while (encoded = next_event)
        deliver(encoded)
      end
    end

    def deliver(encoded)
      result = @transport.send(encoded)
      @diagnostics.increment(result == :accepted ? :sent : :failed)
    rescue StandardError
      @diagnostics.increment(:failed)
    ensure
      @mutex.synchronize do
        @pending -= 1
        @condition.broadcast
      end
    end
  end
end
