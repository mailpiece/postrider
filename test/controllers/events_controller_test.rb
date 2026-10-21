require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  test "the HTML index lists this account's events" do
    deliveries(:queued).track_event("bounced", rcpt_to: "recipient@example.com")
    sign_in_as :nonstaff

    get events_path

    assert_response :success
    assert_select ".trail.trail--events.trail--whole[data-controller=navigable-list] [data-controller=pagination][data-pagination-paginate-on-intersection-value=true]"
    assert_select ".trail__entry[data-navigable-list-target=item] .trail__sentence", text: /Bounced/
  end

  test "the index tells a member a delivery was withheld, and not why" do
    deliveries(:queued).withhold("s3cret phrase")
    sign_in_as :nonstaff

    get events_path

    assert_select ".trail__sentence", text: /Withheld mail to recipient@example.com/
    assert_not_includes response.body, "s3cret phrase"
    assert_not_includes response.body, "blocked phrase"
  end

  test "the index links each event to its own eventable, not just deliveries" do
    webhook = webhooks(:active)
    webhook.track_event("deactivated", consecutive_failures_count: 10)
    sign_in_as :nonstaff

    get events_path

    assert_response :success
    assert_select "a.trail__sentence--link[href=?]", domain_webhook_path(webhook.domain, webhook), text: "Deactivated webhook after 10 failed deliveries"
  end

  test "the index tells an admin a sending token was refused" do
    domain = domains(:example)
    Event.create!(eventable: domain, domain: domain, action: "sending_token_refused", particulars: { token_name: "Example sending token", ip: "198.51.100.12" })
    sign_in_as :leo

    get events_path

    assert_select ".trail__sentence", text: "Refused sending token Example sending token from 198.51.100.12, not in Allowed IPs"
  end

  test "the index keeps a refused sending token from a member" do
    domain = domains(:example)
    Event.create!(eventable: domain, domain: domain, action: "sending_token_refused", particulars: { token_name: "Example sending token", ip: "198.51.100.12" })
    sign_in_as :nonstaff

    get events_path

    assert_not_includes response.body, "198.51.100.12"
  end

  test "the index does not list successful deliveries" do
    deliveries(:delivered).track_event("delivered", rcpt_to: "recipient@example.com")
    sign_in_as :nonstaff

    get events_path

    assert_response :success
    assert_no_match "Delivered mail to", response.body
  end

  test "an event whose eventable has been purged renders unlinked instead of breaking the index" do
    deliveries(:queued).track_event("bounced", rcpt_to: "recipient@example.com")
    Delivery.where(id: deliveries(:queued).id).delete_all
    sign_in_as :nonstaff

    get events_path

    assert_response :success
    assert_select "span.trail__sentence", text: "Bounced mail to recipient@example.com"
  end

  test "a member cannot see the events of a domain they have no access to" do
    bounce_from domains(:private), rcpt_to: "secret@example.com"
    sign_in_as :nonstaff

    get events_path

    assert_response :success
    assert_no_match "secret@example.com", response.body
  end

  test "the creator of a private domain still sees its events" do
    bounce_from domains(:private), rcpt_to: "secret@example.com"
    sign_in_as :leo

    get events_path

    assert_response :success
    assert_select ".trail__sentence", text: /Bounced mail to secret@example.com/
  end

  test "an account cannot see another account's events" do
    Current.with_account(accounts(:other_account)) do
      bounce_from domains(:other_account), rcpt_to: "secret@example.com"
    end
    sign_in_as :nonstaff

    get events_path

    assert_response :success
    assert_no_match "secret@example.com", response.body
  end

  private
    def bounce_from(domain, rcpt_to:)
      create_delivery(domain: domain, rcpt_to: rcpt_to).track_event("bounced", rcpt_to: rcpt_to)
    end
end
