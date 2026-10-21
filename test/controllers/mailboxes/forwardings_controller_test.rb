require "test_helper"

class Mailboxes::ForwardingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @domain = domains(:example)
  end

  test "an admin sends the confirmation again without touching the destination" do
    sign_in_as :leo
    mailbox = mailboxes(:unconfirmed_forwarding)

    assert_enqueued_with job: Mailbox::SendForwardConfirmationJob, args: [ mailbox ] do
      post domain_mailbox_forwardings_path(@domain, mailbox)
    end

    assert_redirected_to domain_mailbox_path(@domain, mailbox)
    assert_equal "unconfirmed@elsewhere.example", mailbox.reload.forward_to
    assert_not mailbox.forwarding?
  end

  test "a mailbox with no destination has nothing to confirm" do
    sign_in_as :leo

    assert_no_enqueued_jobs only: Mailbox::SendForwardConfirmationJob do
      post domain_mailbox_forwardings_path(@domain, mailboxes(:inbox))
    end

    assert_redirected_to domain_mailbox_path(@domain, mailboxes(:inbox))
  end

  test "an unverified domain sends no confirmation and says why" do
    sign_in_as :leo
    domain = domains(:unverified)
    mailbox = domain.mailboxes.create!(local_part: "fwd", forward_to: "someone@elsewhere.example")

    assert_no_enqueued_jobs only: Mailbox::SendForwardConfirmationJob do
      post domain_mailbox_forwardings_path(domain, mailbox)
    end

    assert_redirected_to domain_mailbox_path(domain, mailbox)
    assert_equal "A confirmation can't be sent: check the forwarding address, and verify this domain's DKIM", flash[:alert]
  end

  test "once the domain is verified the confirmation is sent" do
    sign_in_as :leo
    domain = domains(:unverified)
    mailbox = domain.mailboxes.create!(local_part: "fwd", forward_to: "someone@elsewhere.example")
    domain.update!(dkim_status: :ok)

    assert_enqueued_with job: Mailbox::SendForwardConfirmationJob, args: [ mailbox ] do
      post domain_mailbox_forwardings_path(domain, mailbox)
    end

    assert_redirected_to domain_mailbox_path(domain, mailbox)
  end

  test "a member who can see the domain still cannot resend a confirmation" do
    sign_in_as :nonstaff

    assert_no_enqueued_jobs only: Mailbox::SendForwardConfirmationJob do
      post domain_mailbox_forwardings_path(@domain, mailboxes(:forwarding))
    end

    assert_response :forbidden
  end
end
