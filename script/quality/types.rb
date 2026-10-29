# frozen_string_literal: true

module HawkQuality
  class Failure < StandardError; end

  # Coverage is set membership plus exact counts, never a rounded percentage.
  module Types
    def self.verify!(root, rows)
      expected = Dir.glob("lib/**/*.rb", base: root).sort
      observed = rows.map { |row| row.fetch("File") }.sort
      raise Failure, "Type analysis omitted, duplicated, or added runtime files" unless expected == observed

      rows.each { |row| verify_row!(row) }
      verify_policy!(root)
      rows
    end

    def self.verify_row!(row)
      counts = row.values_at("Typed calls", "Untyped calls", "All calls").map { |value| Integer(value, 10) }
      raise Failure, "Failed type analysis: #{row['File']}" unless row["Status"] == "success"

      verify_counts!(counts, row.fetch("File"))
    rescue ArgumentError, TypeError
      raise Failure, "Invalid type statistics: #{row['File']}"
    end

    def self.verify_counts!(counts, path)
      valid = counts.all? { |count| count >= 0 } && counts[1].zero? && counts[0] + counts[1] == counts[2]
      raise Failure, "Untyped calls or invalid statistics: #{path}" unless valid
    end

    def self.verify_output!(output)
      raise Failure, "Steep internal error" if output.match?(/FATAL:|Unexpected error:/)

      output
    end

    def self.verify_policy!(root)
      paths = Dir.glob("{lib/**/*.rb,sig/**/*.rbs}", base: root)
      paths.each do |path|
        source = File.read(File.join(root, path))
        raise Failure, "Untyped declaration or blanket suppression: #{path}" if forbidden?(source)

        verify_narrowing!(path, source)
        RubyVM::InstructionSequence.compile(source, path) if path.end_with?(".rb")
      end
    rescue SyntaxError => e
      raise Failure, e.message
    end

    def self.forbidden?(source)
      source.match?(/@type[^\n]*\buntyped\b|:\s*untyped\b|->\s*untyped\b|@dynamic|steep:ignore|rubocop:disable\s+all/)
    end

    def self.verify_narrowing!(path, source)
      source.lines.each_with_index do |line, index|
        next unless line.include?("#:")

        protocol = line.match?(/#:\s*_Rack(?:File|Enumerable|Callable|Closable)Body\s*$/)
        valid = path == "lib/hawk/rack/body.rb" && protocol
        guards = source.lines[[index - 8, 0].max...index].join
        checked = valid && guards.include?("respond_to?(")
        raise Failure, "Unchecked narrowing: #{path}:#{index + 1}" unless checked
      end
    end
  end
end
