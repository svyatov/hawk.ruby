# frozen_string_literal: true

require "test_helper"

class ReleaseTest < HawkTest
  def test_explicit_revision_takes_precedence
    config = configuration
    config.release = "deploy-42"
    config.detect_release = true

    assert_equal "deploy-42", Hawk::Release.detect(config)
  end

  def test_detection_requires_opt_in
    config = configuration
    config.release = nil

    assert_nil Hawk::Release.detect(config)
  end

  def test_git_revision_matches_checkout
    config = configuration
    config.release = nil
    config.detect_release = true
    expected, = Open3.capture2("git", "rev-parse", "HEAD")

    assert_equal expected.strip, Hawk::Release.detect(config)
  end
end
