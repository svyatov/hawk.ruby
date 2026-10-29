# frozen_string_literal: true

require "test_helper"

class DeliveryTest < HawkTest
  class BlockingTransport
    attr_reader :started, :release, :received

    def initialize
      @started = Queue.new
      @release = Queue.new
      @received = []
    end

    def available?
      true
    end

    def send(encoded)
      @started << true
      @release.pop
      @received << encoded
      :accepted
    end
  end

  def setup
    @transport = BlockingTransport.new
    @diagnostics = Hawk::Diagnostics.new
    config = configuration
    config.queue_capacity = 1
    @delivery = Hawk::Delivery.new(config, transport: @transport, diagnostics: @diagnostics)
  end

  def teardown
    5.times { @transport.release << true }
    @delivery.close(timeout: 1.0)
  end

  def test_full_queue_rejects_without_waiting
    assert @delivery.enqueue("active", "first")
    @transport.started.pop
    assert @delivery.enqueue("queued", "second")
    refute @delivery.enqueue("overflow", "third")
    assert_equal 1, @diagnostics.snapshot.fetch(:overflow)
    2.times { @transport.release << true }
    assert @delivery.flush(timeout: 1.0)
    assert_equal %w[first second], @transport.received
  end

  def test_flush_deadline_and_close_stop_acceptance
    @delivery.enqueue("active", "first")
    @transport.started.pop

    refute @delivery.flush(timeout: 0.01)
    refute @delivery.close(timeout: 0.01)
    refute @delivery.enqueue("late", "late")
    @transport.release << true
    assert @delivery.flush(timeout: 1.0)
  end

  def test_queue_takes_immutable_snapshot
    original = +"original"
    @delivery.enqueue("event", original)
    @transport.started.pop
    original.replace("changed")
    @transport.release << true
    @delivery.flush(timeout: 1.0)

    assert_equal ["original"], @transport.received
  end

  def test_child_resets_inherited_queue_before_acquiring_parent_lock
    @delivery.enqueue("active", "parent-active")
    @transport.started.pop
    @delivery.enqueue("queued", "parent-queued")
    result = with_held_delivery_mutex { child_delivery_result }

    assert_equal [true, true, ["child-only"]], result
  end

  private

  def child_delivery_result
    reader, writer = IO.pipe
    child = fork { write_child_result(reader, writer) }
    writer.close
    result = JSON.parse(reader.read)
    Process.wait(child)
    result
  ensure
    reader&.close
    writer&.close unless writer&.closed?
  end

  def write_child_result(reader, writer)
    reader.close
    @transport.release << true
    accepted = @delivery.enqueue("child", "child-only")
    completed = @delivery.flush(timeout: 0.5)
    writer.write(JSON.generate([accepted, completed, @transport.received]))
    writer.close
    exit! 0
  end

  def with_held_delivery_mutex
    entered = Queue.new
    release = Queue.new
    mutex = @delivery.instance_variable_get(:@mutex)
    holder = Thread.new do
      mutex.synchronize do
        entered << true
        release.pop
      end
    end
    entered.pop
    yield
  ensure
    release << true
    holder&.join
  end
end
