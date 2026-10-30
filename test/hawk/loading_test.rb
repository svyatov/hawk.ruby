# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require_relative "../support/subprocess"

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

  def test_package_name_loads_the_core_and_rack_without_frameworks
    output, error, status = Subprocess.run(<<~RUBY)
      before = Thread.list.size
      require "hawk-ruby"
      require "hawk"
      abort "framework loaded" if %i[Rails Rack Sidekiq Resque Delayed Rake].any? { |name| Object.const_defined?(name) }
      abort "worker started" unless before == Thread.list.size
      print Hawk::Rack.new(->(_) { [200, {}, ["ok"]] }).call({}).first
    RUBY

    assert status.success?, error
    assert_equal "200", output
  end

  def test_rake_is_discovered_in_either_startup_order
    [%w[rake hawk], %w[hawk rake]].each do |libraries|
      output, error, status = Subprocess.run(<<~RUBY)
        #{libraries.map { |library| "require #{library.inspect}" }.join("\n")}
        2.times { Hawk.init { |config| config.token = nil } }
        Rake::Task.define_task("plain") { print "ran" }
        Rake::Task["plain"].invoke
        print Rake::Task.ancestors.count { |ancestor| ancestor == Hawk::Rake::TaskMethods }
      RUBY

      assert status.success?, error
      assert_equal "ran1", output
    end
  end

  def test_explicit_rack_entry_point_loads_the_core
    output, error, status = Subprocess.run(<<~RUBY)
      require "hawk/rack"
      print Hawk::Rack.new(->(_) { [200, {}, ["ok"]] }).call({}).first
    RUBY

    assert status.success?, error
    assert_equal "200", output
  end
end
