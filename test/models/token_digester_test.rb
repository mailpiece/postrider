require "test_helper"

class TokenDigesterTest < ActiveSupport::TestCase
  test "a digest is lowercase hex HMAC-SHA256 under the pepper" do
    with_pepper "key" do
      assert_equal "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8",
        TokenDigester.digest("The quick brown fox jumps over the lazy dog")
    end
  end

  test "the pepper is read from OAUTH_TOKEN_PEPPER" do
    with_env "p" * 32 do
      assert_equal "p" * 32, TokenDigester.send(:pepper)
    end
  end

  test "a short pepper is refused" do
    with_env "p" * 31 do
      assert_raises(TokenDigester::MissingPepper) { TokenDigester.verify_pepper! }
    end
  end

  test "without OAUTH_TOKEN_PEPPER the pepper is derived from secret_key_base" do
    with_env nil do
      assert_equal Rails.application.key_generator.generate_key("token_digest_pepper", 32), TokenDigester.send(:pepper)
    end
  end

  private
    def with_pepper(pepper)
      original = TokenDigester.instance_variable_get(:@pepper)
      TokenDigester.instance_variable_set(:@pepper, pepper)
      yield
    ensure
      TokenDigester.instance_variable_set(:@pepper, original)
    end

    def with_env(value)
      original = ENV["OAUTH_TOKEN_PEPPER"]
      ENV["OAUTH_TOKEN_PEPPER"] = value
      with_pepper(nil) { yield }
    ensure
      ENV["OAUTH_TOKEN_PEPPER"] = original
    end
end
