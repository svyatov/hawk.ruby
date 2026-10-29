# frozen_string_literal: true

require "test_helper"

class TokenTest < HawkTest
  def test_endpoint_uses_standard_https
    token = Hawk::Token.decode(integration_token)

    assert_equal "https://project-123.k1.hawk.so", token.endpoint.to_s
    assert_equal 443, token.endpoint.port
  end

  def test_malformed_tokens_raise_without_disclosing_input
    malformed = ["not-base64", "A" * 8193, Base64.strict_encode64("{"), Base64.strict_encode64("[]")]
    malformed.each do |value|
      error = assert_raises(Hawk::ConfigurationError) { Hawk::Token.decode(value) }

      refute_includes error.message, value
    end
  end

  def test_unsafe_dns_labels_are_rejected
    ["-start", "end-", "two.labels", "x/y", "x\nHost:evil", "a" * 64, "", "☃"].each do |label|
      assert_raises(Hawk::ConfigurationError) { Hawk::Token.decode(integration_token(id: label)) }
    end
  end

  def test_valid_dns_boundary_is_accepted
    assert_equal "https://#{'a' * 63}.k1.hawk.so", Hawk::Token.decode(integration_token(id: "a" * 63)).endpoint.to_s
  end

  def test_secret_must_be_a_nonempty_string
    ["", nil, 1, []].each do |secret|
      assert_raises(Hawk::ConfigurationError) { Hawk::Token.decode(integration_token(secret: secret)) }
    end
  end
end
