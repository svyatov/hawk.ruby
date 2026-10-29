# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class SourceTest < HawkTest
  class MissingLocation < RuntimeError
    def backtrace_locations
      [Struct.new(:absolute_path, :path, :lineno, :base_label).new(nil, nil, 1, "unknown")]
    end
  end

  class GrowingSource < Hawk::Source
    private

    def readable_path(path)
      resolved = super
      File.write(resolved, "x" * 1_048_577) if resolved
      resolved
    end
  end

  class RemovedSource < Hawk::Source
    private

    def readable_path(path)
      resolved = super
      File.unlink(resolved) if resolved
      resolved
    end
  end

  def test_a_file_removed_after_validation_keeps_the_frame_without_source
    Dir.mktmpdir do |root|
      path = File.join(root, "removed.rb")
      File.write(path, "before\n")
      config = configuration
      config.source_roots = [root]
      error = RuntimeError.new
      error.set_backtrace(["#{path}:1"])

      frame = RemovedSource.new(config).frames(error).first
      assert_equal path, frame.fetch("file")
      refute frame.key?("sourceCode")
    end
  end

  def test_invalid_locations_and_nonpositive_lines_are_omitted
    source = Hawk::Source.new(configuration)
    assert_empty source.frames(MissingLocation.new)
    error = RuntimeError.new
    error.set_backtrace(["#{__FILE__}:0"])
    assert_empty source.frames(error)
  end

  def test_files_that_grow_after_validation_are_not_read_as_source
    Dir.mktmpdir do |root|
      path = File.join(root, "growing.rb")
      File.write(path, "before\n")
      error = RuntimeError.new
      error.set_backtrace(["#{path}:1"])
      config = configuration
      config.source_roots = [root]

      refute GrowingSource.new(config).frames(error).first.key?("sourceCode")
      error.set_backtrace(["#{root}/growing.rb:1"])
      refute Hawk::Source.new(config).frames(error).first.key?("sourceCode")
    end
  end

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
