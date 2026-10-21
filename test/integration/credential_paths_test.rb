require "test_helper"

# Every route carrying a credential in its path is declared in config/routes.rb: a renamed route or
# parameter fails here rather than logging the credential.
class CredentialPathsTest < ActiveSupport::TestCase
  include FilterPathParameters::Assertions
  include Rails.application.routes.url_helpers

  setup do
    @slug = accounts(:davids_account).slug
  end

  test "a qr code's signed id is filtered" do
    assert_path_filtered qr_code_path("made-up-signed-id", script_name: @slug), "made-up-signed-id"
  end

  test "a join code is filtered" do
    assert_path_filtered join_path("made-up-code", script_name: @slug), "made-up-code"
  end

  test "a join code is filtered past the route" do
    assert_path_filtered "#{join_path("made-up-code", script_name: @slug)}/xmlrpc.php", "made-up-code"
  end

  test "a session transfer id is filtered" do
    assert_path_filtered session_transfer_path("made-up-transfer-id", script_name: nil), "made-up-transfer-id"
  end

  test "a forwarding confirmation token is filtered" do
    path = domain_mailbox_forwarding_confirmation_path("domain-id", "mailbox-id", "made-up-token", script_name: @slug)

    assert_path_filtered path, "made-up-token"
  end
end
