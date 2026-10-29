# frozen_string_literal: true

require "test_helper"
require_relative "../../script/quality/crap"

class CrapGateTest < HawkTest
  def test_unknown_low_complexity_scores_fail_even_if_the_cli_threshold_can_pass
    report = "CRAP Report\n===========\nFunction Namespace CC Cov% CRAP\n---\nmethod Example 1 N/A N/A\nfooter\n"

    assert_raises(HawkQuality::Failure) { HawkQuality::Crap.verify_output!(report) }
  end

  def test_empty_reports_fail
    assert_raises(HawkQuality::Failure) { HawkQuality::Crap.verify_output!("") }
  end

  def test_fully_measured_reports_pass
    report = "CRAP Report\n===========\nFunction Namespace CC Cov% CRAP\n---\nmethod Example 1 100.0% 1.0\nfooter\n"

    assert_equal report, HawkQuality::Crap.verify_output!(report)
  end
end
