require "test_helper"

class Mailboxes::Forwardings::ConfirmationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @domain = domains(:example)
    @mailbox = mailboxes(:unconfirmed_forwarding)
    @token = token_for(@mailbox)
  end

  test "the confirmation page names both endpoints without confirming anything" do
    get domain_mailbox_forwarding_confirmation_path(@domain, @mailbox, @token)

    assert_response :success
    assert_match @mailbox.address, response.body
    assert_match @mailbox.forward_to, response.body
    assert_not @mailbox.reload.forwarding?
  end

  test "the confirmation page names nothing for a token that does not check out" do
    get domain_mailbox_forwarding_confirmation_path(@domain, @mailbox, "not-a-token")

    assert_response :not_found
    assert_no_match @mailbox.address, response.body
    assert_no_match @mailbox.forward_to, response.body
  end

  test "the confirmation page names nothing once the token has expired" do
    travel_to 25.hours.from_now do
      get domain_mailbox_forwarding_confirmation_path(@domain, @mailbox, @token)
    end

    assert_response :not_found
  end

  test "posting the emailed token confirms forwarding for someone with no session at all" do
    post domain_mailbox_forwarding_confirmation_path(@domain, @mailbox, @token), params: { forwarding_token: @token }

    assert_redirected_to domain_mailbox_forwarding_confirmation_path(@domain, @mailbox, @token)
    assert @mailbox.reload.forwarding?
    assert_nil cookies[:session_token].presence
  end

  test "the confirmation page reports a forwarding that is already confirmed" do
    @mailbox.confirm_forwarding

    get domain_mailbox_forwarding_confirmation_path(@domain, @mailbox, @token)

    assert_response :success
    assert_match "Forwarding confirmed", response.body
  end

  test "an expired token confirms nothing" do
    travel_to 25.hours.from_now do
      post domain_mailbox_forwarding_confirmation_path(@domain, @mailbox, @token), params: { forwarding_token: @token }
    end

    assert_response :unprocessable_entity
    assert_not @mailbox.reload.forwarding?
  end

  test "a token issued for one mailbox cannot confirm another" do
    other = @domain.mailboxes.create!(local_part: "other", forward_to: "someone@example.com")

    post domain_mailbox_forwarding_confirmation_path(@domain, other, @token), params: { forwarding_token: @token }

    assert_response :unprocessable_entity
    assert_not other.reload.forwarding?
  end

  test "changing the destination retires the outstanding token" do
    @mailbox.update! forward_to: "elsewhere@example.com"

    post domain_mailbox_forwarding_confirmation_path(@domain, @mailbox, @token), params: { forwarding_token: @token }

    assert_response :unprocessable_entity
    assert_not @mailbox.reload.forwarding?
  end

  test "another account's mailbox is out of reach" do
    other_mailbox = domains(:other_account).mailboxes.create!(local_part: "hello", forward_to: "someone@example.com")
    other_token = token_for(other_mailbox)

    post domain_mailbox_forwarding_confirmation_path(domains(:other_account), other_mailbox, other_token),
      params: { forwarding_token: other_token }

    assert_response :not_found
    assert_not other_mailbox.reload.forwarding?
  end

  private
    def token_for(mailbox)
      mailbox.send(:generate_forward_confirmation_token)
    end
end
