# frozen_string_literal: true

require "minitest/autorun"
require "open3"

class LoadingTest < Minitest::Test
  def test_plain_require_does_not_load_frameworks_or_start_threads
    script = <<~RUBY
      before = Thread.list.size
      require "hawk"
      abort "Rails loaded" if Object.const_defined?(:Rails)
      abort "Sidekiq loaded" if Object.const_defined?(:Sidekiq)
      abort "worker started" unless before == Thread.list.size
      puts Hawk::VERSION
    RUBY
    output, error, status = Open3.capture3("ruby", "-Ilib", "-e", script)

    assert status.success?, error
    assert_equal "0.1.1\n", output
  end
end
