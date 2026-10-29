# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < HawkTest
  def test_missing_token_disables_capture
    config = configuration
    config.token = nil
    config.validate!

    refute config.enabled?
  end

  def test_empty_token_disables_capture
    config = configuration
    config.token = ""
    config.validate!

    refute config.enabled?
  end

  def test_environment_controls_capture
    config = configuration
    config.environment = "test"
    config.enabled_environments = ["production"]
    config.validate!

    refute config.enabled?
    config.enabled_environments = ["test"]
    assert config.enabled?
  end

  def test_supplied_malformed_token_raises
    config = configuration
    config.token = "bad"

    assert_raises(Hawk::ConfigurationError) { config.validate! }
  end

  def test_sampling_rejects_out_of_range_and_nonfinite_values
    [-0.1, 1.1, Float::NAN, Float::INFINITY, "1"].each do |rate|
      config = configuration
      config.sample_rate = rate

      assert_raises(Hawk::ConfigurationError) { config.validate! }
    end
  end

  def test_capacity_and_deadline_validation
    [[:queue_capacity, 0], [:queue_capacity, -1], [:queue_capacity, 1.5],
     [:read_timeout, -1.0], [:read_timeout, "1"], [:flush_timeout, Float::INFINITY]].each do |key, value|
      config = configuration
      config.public_send("#{key}=", value)

      assert_raises(Hawk::ConfigurationError) { config.validate! }
    end
  end

  def test_custom_endpoints_require_https_or_loopback_http
    ["http://example.com", "https://user:pass@example.com", "ftp://example.com",
     "https://example.com/#fragment"].each do |url|
      config = configuration
      config.endpoint = url

      assert_raises(Hawk::ConfigurationError) { config.validate! }
    end
    config = configuration
    config.endpoint = "http://127.0.0.1:1234"
    config.validate!

    assert_equal "http://127.0.0.1:1234", config.collector_uri.to_s
  end

  def test_validates_delivery_mode_and_callback
    config = configuration
    config.delivery_mode = :unknown
    assert_raises(Hawk::ConfigurationError) { config.validate! }
    config.delivery_mode = :sync
    config.before_send = "not callable"
    assert_raises(Hawk::ConfigurationError) { config.validate! }
  end
end
