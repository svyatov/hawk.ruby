# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class SourceTest < HawkTest
  def test_fallback_backtrace_extracts_source_at_file_boundary
    Dir.mktmpdir do |root|
      path = File.join(root, "example.rb")
      File.write(path, "first\nsecond\nthird\n")
      error = RuntimeError.new("failed")
      error.set_backtrace(["#{path}:1:in 'run'", "#{path}:3:in 'main'"])
      config = configuration
      config.source_roots = [root]
      frames = Hawk::Source.new(config).frames(error)

      assert_equal([1, 3], frames.map { |frame| frame.fetch("line") })
      assert_equal "run", frames.first.fetch("function")
      assert_equal({ "line" => 1, "content" => "first" }, frames.first.fetch("sourceCode").first)
    end
  end

  def test_missing_or_outside_source_does_not_remove_frames
    config = configuration
    error = RuntimeError.new("failed")
    error.set_backtrace(["/missing/path.rb:42:in 'run'", "malformed"])
    frames = Hawk::Source.new(config).frames(error)

    assert_equal 1, frames.size
    assert_equal 42, frames.first.fetch("line")
    refute frames.first.key?("sourceCode")
  end

  def test_symlink_escape_does_not_read_outside_root
    Dir.mktmpdir do |outer|
      root = File.join(outer, "allowed")
      Dir.mkdir(root)
      secret = File.join(outer, "secret.rb")
      File.write(secret, "outside-root-secret\n")
      path = File.join(root, "linked.rb")
      File.symlink(secret, path)
      config = configuration
      config.source_roots = [root]
      error = RuntimeError.new("failed")
      error.set_backtrace(["#{path}:1"])

      refute Hawk::Source.new(config).frames(error).first.key?("sourceCode")
    end
  end

  def test_source_can_be_disabled_and_unraised_exception_is_empty
    config = configuration
    config.send_source = false
    error = RuntimeError.new("failed")

    assert_empty Hawk::Source.new(config).frames(error)
    error.set_backtrace(["#{__FILE__}:1"])
    refute Hawk::Source.new(config).frames(error).first.key?("sourceCode")
  end

  def test_source_at_first_line_includes_only_five_following_lines
    Dir.mktmpdir do |root|
      path = File.join(root, "example.rb")
      File.write(path, (1..20).map { |line| "line#{line}\n" }.join)
      error = RuntimeError.new("failed")
      error.set_backtrace(["#{path}:1"])
      config = configuration
      config.source_roots = [root]

      assert_equal([1, 2, 3, 4, 5, 6], Hawk::Source.new(config).frames(error).first.fetch("sourceCode").map do |entry|
        entry.fetch("line")
      end)
    end
  end
end
