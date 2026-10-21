require "test_helper"

class Webhooks::DeliveriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @webhook = webhooks(:active)
  end

  test "the JSON index lists deliveries with a sanitized request and response summary" do
    sign_in_as :leo
    delivery = @webhook.deliveries.create!(event: inbound_event, state: :completed,
      response: { code: 200 },
      request: { headers: { "User-Agent" => "postrider", "X-Webhook-Signature" => "secret" } })

    get domain_webhook_deliveries_path(@webhook.domain, @webhook)

    assert_response :success
    row = response.parsed_body.sole
    assert_equal delivery.id, row["id"]
    assert_equal "completed", row["state"]
    assert row["updated_at"].present?
    assert_equal delivery.event_id, row["event"]["id"]
    assert_equal "inbound_email_received", row["event"]["action"]
    assert row["event"]["created_at"].present?
    assert_equal 200, row["response"]["code"]
    assert_not row["request"]["headers"].key?("X-Webhook-Signature")
  end

  test "a pending delivery renders a null request and response" do
    sign_in_as :leo
    @webhook.deliveries.create!(event: inbound_event)

    get domain_webhook_deliveries_path(@webhook.domain, @webhook)

    assert_response :success
    row = response.parsed_body.sole
    assert_nil row["request"]
    assert_nil row["response"]
  end

  test "a non-admin is forbidden" do
    sign_in_as :nonstaff

    get domain_webhook_deliveries_path(@webhook.domain, @webhook)

    assert_response :forbidden
  end

  test "cannot list another account's webhook deliveries" do
    sign_in_as :leo
    webhook = webhooks(:other_account)

    get domain_webhook_deliveries_path(webhook.domain, webhook)

    assert_response :not_found
  end

  private
    def inbound_event
      Event.create!(domain: domains(:example), action: "inbound_email_received", eventable: inbound_emails(:received))
    end
end
