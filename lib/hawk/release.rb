# frozen_string_literal: true

require "open3"

module Hawk
  # Git is consulted only during explicit initialization-time detection.
  module Release
    def self.detect(configuration)
      return configuration.release if configuration.release
      return unless configuration.detect_release

      git_revision
    end

    def self.git_revision
      Open3.popen3("git", "rev-parse", "HEAD") do |input, output, _error, waiter|
        input.close
        unless waiter.join(1.0)
          Process.kill("KILL", waiter.pid)
          waiter.join
          return nil
        end

        revision = output.read(128)
        revision&.strip if waiter.value.success?
      end
    rescue SystemCallError, IOError
      nil
    end
  end
end
