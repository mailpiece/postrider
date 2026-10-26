require "test_helper"

class Identity::AccessTokenTest < ActiveSupport::TestCase
  setup do
    @identity = identities(:leo)
  end

  test "assigns a digest on create and never persists the raw token" do
    access_token = @identity.access_tokens.create!(description: "API", permission: :write)
    plaintext = access_token.token

    assert plaintext.present?
    assert_equal TokenDigester.digest(plaintext), access_token.token_digest
    assert_nil Identity::AccessToken.find(access_token.id).token
    assert_equal access_token, Identity::AccessToken.authenticate(plaintext)
  end

  test "a new token names its kind" do
    assert_match(/\Apostrider_pat_[1-9A-HJ-NP-Za-km-z]{44}\z/, @identity.access_tokens.create!(description: "API").token)
  end

  test "fixture token authenticates by digest" do
    assert_equal @identity, Identity.find_by_permissable_access_token("test_token_davids_api_0000000000", method: "GET")
  end
end
