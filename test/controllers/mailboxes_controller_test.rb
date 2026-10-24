require "test_helper"

class MailboxesControllerTest < ActionDispatch::IntegrationTest
  test "an API client with a write access token provisions a mailbox" do
    assert_difference -> { domains(:example).mailboxes.count }, 1 do
      post domain_mailboxes_path(domains(:example)), params: { mailbox: { local_part: "sales" } },
        headers: api_token_env, as: :json
    end

    assert_response :created
    body = response.parsed_body
    mailbox = domains(:example).mailboxes.order(:created_at).last
    assert_equal mailbox.id, body["id"]
    assert_equal "sales", body["local_part"]
    assert_equal domains(:example).name, body["domain"]
  end

  test "the API lists a domain's mailboxes" do
    mailbox = mailboxes(:inbox)

    get domain_mailboxes_path(domains(:example)), headers: api_token_env, as: :json

    assert_response :success
    entry = response.parsed_body.find { |m| m["id"] == mailbox.id }
    assert_equal "inbox", entry["local_part"]
    assert_equal domains(:example).name, entry["domain"]
  end

  test "the API shows a mailbox" do
    mailbox = mailboxes(:inbox)

    get domain_mailbox_path(domains(:example), mailbox), headers: api_token_env, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal mailbox.id, body["id"]
    assert_equal "inbox", body["local_part"]
    assert_equal domains(:example).name, body["domain"]
  end

  test "the API revokes a mailbox" do
    mailbox = mailboxes(:inbox)

    assert_difference -> { domains(:example).mailboxes.count }, -1 do
      delete domain_mailbox_path(domains(:example), mailbox), headers: api_token_env, as: :json
    end

    assert_response :no_content
  end

  test "a read-only access token cannot provision a mailbox" do
    read_only = identities(:leo).access_tokens.create!(permission: :read, description: "Read only")

    assert_no_difference -> { domains(:example).mailboxes.count } do
      post domain_mailboxes_path(domains(:example)), params: { mailbox: { local_part: "nope" } },
        headers: bearer_token_env(read_only.token), as: :json
    end

    assert_response :unauthorized
  end

  test "an unauthenticated request cannot provision a mailbox" do
    assert_no_difference -> { domains(:example).mailboxes.count } do
      post domain_mailboxes_path(domains(:example)), params: { mailbox: { local_part: "nope" } }, as: :json
    end

    assert_not_equal 201, response.status
  end

  test "a member cannot provision a mailbox" do
    member_token = identities(:nonstaff).access_tokens.create!(permission: :write, description: "Member")

    assert_no_difference -> { Mailbox.count } do
      post domain_mailboxes_path(domains(:private)), params: { mailbox: { local_part: "nope" } },
        headers: bearer_token_env(member_token.token), as: :json
    end

    assert_response :not_found
  end

  test "another account's domain cannot be provisioned against" do
    assert_no_difference -> { Mailbox.count } do
      post domain_mailboxes_path(domains(:other_account)), params: { mailbox: { local_part: "sneaky" } },
        headers: api_token_env, as: :json
    end

    assert_response :not_found
  end

  test "creating a mailbox in the browser redirects to its show page, with a success flash" do
    sign_in_as :leo

    post domain_mailboxes_path(domains(:example)), params: { mailbox: { local_part: "hello" } }

    mailbox = domains(:example).mailboxes.order(:created_at).last
    assert_redirected_to domain_mailbox_path(domains(:example), mailbox)
    follow_redirect!
    assert_match "Mailbox added", response.body
  end

  test "show renders the mailbox page" do
    sign_in_as :leo
    mailbox = mailboxes(:inbox)

    get domain_mailbox_path(domains(:example), mailbox)

    assert_response :success
    assert_select ".breadcrumbs strong", text: "inbox@#{domains(:example).name}"
    assert_select ".record .status", text: "Off"
    assert_select ".trail__sentence", text: "Mailbox added"
    assert_select ".strip a[href=?][aria-keyshortcuts=e]", edit_domain_mailbox_path(domains(:example), mailbox), text: /Edit/
    assert_select ".record a[href=?]", edit_domain_mailbox_path(domains(:example), mailbox), text: "Set up forwarding"
  end

  test "show calls an unconfirmed destination not confirmed, whether it never confirmed or a bounce cleared it" do
    sign_in_as :leo
    mailbox = mailboxes(:unconfirmed_forwarding)

    get domain_mailbox_path(domains(:example), mailbox)

    assert_select ".record .status", text: "Not confirmed"
    assert_select ".record__byline", text: /Set to forward to\s+unconfirmed@elsewhere.example/
    assert_select "button", text: "Send a confirmation link"
    assert_select ".strip a[href=?]", edit_domain_mailbox_path(domains(:example), mailbox), text: /Edit/
    assert_select ".record a[href=?]", edit_domain_mailbox_path(domains(:example), mailbox), count: 0
  end

  test "a forward on an unverified domain is saved unconfirmed, sends nothing, and asks for DKIM" do
    sign_in_as :leo
    mailbox = mailboxes(:unverified_postmaster)

    assert_no_enqueued_jobs only: Mailbox::SendForwardConfirmationJob do
      patch domain_mailbox_path(domains(:unverified), mailbox), params: { mailbox: { forward_to: "someone@example.com" } }
    end

    follow_redirect!
    assert_no_match "Confirmation sent", response.body
    assert_select ".record p", text: "Verify this domain's DKIM, then send the confirmation."
    assert_select ".record a[href=?]", domain_dns_records_path(domains(:unverified)), text: "See the DNS records"
    assert_select "button", text: "Send a confirmation link", count: 0
    assert_equal "someone@example.com", mailbox.reload.forward_to
  end

  test "duplicate local-parts on the same domain are rejected" do
    sign_in_as :leo

    assert_no_difference -> { domains(:example).mailboxes.count } do
      post domain_mailboxes_path(domains(:example)), params: { mailbox: { local_part: "inbox" } }
    end

    assert_response :unprocessable_entity
  end

  test "a reserved mailbox cannot be removed and offers no remove control" do
    sign_in_as :leo
    reserved = mailboxes(:example_postmaster)

    get domain_mailbox_path(domains(:example), reserved)
    assert_response :success
    assert_select "button", text: /Remove this mailbox/, count: 0

    assert_no_difference -> { domains(:example).mailboxes.count } do
      delete domain_mailbox_path(domains(:example), reserved)
    end
    assert domains(:example).mailboxes.exists?(reserved.id)
  end

  test "the index lists the mailboxes under a row leading to the catch-all policy" do
    sign_in_as :leo
    mailboxes(:example_postmaster).update!(forward_to: "someone@example.com")

    get domain_mailboxes_path(domains(:example))

    assert_response :success
    assert_select "select", count: 0
    assert_select ".rows--links a.row__body[href=?]", edit_domain_catch_all_path(domains(:example)) do
      assert_select ".row__title", text: "Everything else"
      assert_select ".row__meta", text: "Mail for an address with no mailbox is rejected"
    end
    assert_select "input[placeholder=?]", "Filter mailboxes…"
    assert_select ".filter__empty a", count: 0
    assert_select "[data-controller=pagination][data-pagination-paginate-on-intersection-value=true]"
    assert_select "li.row[data-quick-find-target=item] a.row__body" do
      assert_select ".row__title", text: "postmaster@#{domains(:example).name}"
      assert_select ".row__meta", text: "Not confirmed by someone@example.com · Required", count: 1
      assert_select ".row__meta .status", text: "Not confirmed by someone@example.com"
    end
  end

  test "setting a forwarding address sends a confirmation link and says where it went" do
    sign_in_as :leo
    mailbox = mailboxes(:inbox)

    assert_enqueued_with job: Mailbox::SendForwardConfirmationJob, args: [ mailbox ] do
      patch domain_mailbox_path(domains(:example), mailbox), params: { mailbox: { forward_to: "someone@example.com" } }
    end

    assert_redirected_to domain_mailbox_path(domains(:example), mailbox)
    follow_redirect!
    assert_match "Confirmation sent to someone@example.com", response.body
    assert_equal "someone@example.com", mailbox.reload.forward_to
    assert_not mailbox.forwarding?
  end

  test "clearing the forwarding address sends nothing" do
    sign_in_as :leo
    mailbox = mailboxes(:forwarding)

    assert_no_enqueued_jobs only: Mailbox::SendForwardConfirmationJob do
      patch domain_mailbox_path(domains(:example), mailbox), params: { mailbox: { forward_to: "" } }
    end

    assert_nil mailbox.reload.forward_to
  end

  test "setting forwarding addresses is rate limited by the hour" do
    sign_in_as :leo
    Rails.cache.stubs(:increment).returns(6)

    assert_no_enqueued_jobs only: Mailbox::SendForwardConfirmationJob do
      patch domain_mailbox_path(domains(:example), mailboxes(:inbox)), params: { mailbox: { forward_to: "someone@example.com" } }
    end

    assert_response :too_many_requests
  end

  test "edit renders the forwarding form" do
    sign_in_as :leo
    mailbox = mailboxes(:inbox)

    get edit_domain_mailbox_path(domains(:example), mailbox)

    assert_response :success
    assert_select "input[name=?]", "mailbox[forward_to]"
  end

  test "creating a mailbox with a forwarding address sends a confirmation" do
    sign_in_as :leo

    assert_enqueued_jobs 1, only: Mailbox::SendForwardConfirmationJob do
      post domain_mailboxes_path(domains(:example)), params: { mailbox: { local_part: "fwd", forward_to: "someone@example.com" } }
    end

    mailbox = domains(:example).mailboxes.find_by!(local_part: "fwd")
    assert_equal "someone@example.com", mailbox.forward_to
    assert_not mailbox.forwarding?
  end
end
