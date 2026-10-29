# frozen_string_literal: true

require_relative "types"

module HawkQuality
  # The CLI permits bounded unknown scores; this project requires measured scores.
  module Crap
    def self.verify_output!(report)
      raise Failure, "Unknown CRAP method scores" if report.match?(%r{\sN/A(?:\s|$)})
      raise Failure, "Empty CRAP report" unless report.lines.size > 5 && report.include?("Cov%")

      report
    end
  end
end
