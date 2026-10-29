# frozen_string_literal: true

module Hawk
  # Backtraces remain useful when source files are unavailable or excluded.
  class Source
    def initialize(configuration)
      @enabled = configuration.send_source
      @roots = configuration.source_roots.filter_map { |root| realpath(root) }
    end

    def frames(exception)
      locations = exception.backtrace_locations
      if locations && !locations.empty?
        locations.take(100).filter_map { |location| location_frame(location) }
      else
        (exception.backtrace || []).take(100).filter_map { |line| parse(line) }
      end
    rescue StandardError
      []
    end

    private

    def location_frame(location)
      path = location.absolute_path || location.path
      frame(path, location.lineno, location.base_label) if path
    end

    def realpath(path)
      File.realpath(path)
    rescue SystemCallError, ArgumentError
      nil
    end

    def parse(value)
      match = /\A(.+):(\d+)(?::in [`'](.*)[`'])?\z/.match(value)
      return unless match

      frame(match[1].to_s, match[2].to_i, match[3])
    end

    def frame(path, line, function)
      return unless line.positive?

      # @type var result: payload
      result = { "file" => path, "line" => line }
      result["function"] = function if function
      snippets = snippets(path, line)
      result["sourceCode"] = snippets unless snippets.empty?
      result
    end

    def snippets(path, line)
      return [] unless @enabled

      resolved = readable_path(path)
      return [] unless resolved

      content = File.binread(resolved, 1_048_577)
      return [] if content.bytesize > 1_048_576

      excerpt(content, line)
    rescue SystemCallError, IOError, ArgumentError
      []
    end

    def readable_path(path)
      resolved = realpath(path)
      return unless resolved && @roots.any? { |root| resolved.start_with?("#{root}/") }

      resolved if File.file?(resolved) && File.size(resolved) <= 1_048_576
    end

    def excerpt(content, line)
      lines = content.force_encoding(Encoding::UTF_8).scrub.lines
      first = [line - 6, 0].max
      width = [line + 5 - first, 11].min
      (lines[first, width] || []).each_with_index.map do |text, index|
        { "line" => first + index + 1, "content" => text.chomp }
      end
    end
  end
end
