# frozen_string_literal: true

require "test_helper"

class DeliveryFailuresTest < HawkTest
  class Transport
    attr_accessor :available, :failure, :callback
    attr_reader :results

    def initialize
      @available = true
      @results = Queue.new
    end

    def available?
      @available
    end

    def send(_encoded)
      raise @failure if @failure

      @results << @callback.call if @callback
      :accepted
    end
  end

  def setup
    @transport = Transport.new
    @diagnostics = Hawk::Diagnostics.new
    @delivery = Hawk::Delivery.new(configuration, transport: @transport, diagnostics: @diagnostics)
  end

  def teardown
    @delivery.close(timeout: 1.0)
  end

  def test_unavailable_transport_rejects_without_queueing
    @transport.available = false

    refute @delivery.enqueue("limited", "{}")
    assert @delivery.flush(timeout: 0.0)
  end

  def test_worker_transport_failure_completes_pending_delivery
    @transport.failure = IOError.new("transport failed")
    assert @delivery.enqueue("failed", "{}")
    assert @delivery.flush(timeout: 1.0)
    assert_equal 1, @diagnostics.snapshot[:failed]
  end

  def test_worker_callback_cannot_flush_itself
    @transport.callback = -> { @delivery.flush(timeout: 1.0) }
    @delivery.enqueue("callback", "{}")

    assert_equal false, @transport.results.pop
    assert @delivery.flush(timeout: 1.0)
  end

  def test_invalid_flush_deadlines_return_false
    refute @delivery.flush(timeout: -1.0)
    refute @delivery.flush(timeout: Float::NAN)
  end

  def test_fork_flush_close_and_diagnostics_reset_before_use
    @diagnostics.increment(:parent)
    results = child_result do
      [@delivery.flush(timeout: 0.1), @delivery.close(timeout: 0.1), @diagnostics.snapshot]
    end
    assert_equal [true, true, {}], results
    assert @delivery.enqueue("parent", "{}")
  end

  def test_fork_close_can_be_the_first_delivery_operation
    assert_equal(true, child_result { @delivery.close(timeout: 0.1) })
  end

  private

  def child_result
    reader, writer = IO.pipe
    child = fork do
      reader.close
      writer.write(JSON.generate(yield))
      writer.close
      exit! 0
    end
    writer.close
    result = JSON.parse(reader.read)
    Process.wait(child)
    result
  ensure
    reader&.close
    writer&.close unless writer&.closed?
  end
end
