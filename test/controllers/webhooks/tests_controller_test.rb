require "test_helper"

class Webhooks::TestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @webhook = webhooks(:active)
    stub_dns_resolution("93.184.216.34")
  end

  test "sends a test to this webhook only" do
    sign_in_as :leo

    assert_difference -> { @webhook.deliveries.count }, 1 do
      assert_no_difference -> { Webhook::Delivery.where.not(webhook: @webhook).count } do
        post domain_webhook_test_path(@webhook.domain, @webhook)
        perform_enqueued_jobs only: Event::WebhookDispatchJob
      end
    end

    assert_redirected_to @webhook
    assert_equal "Test sent. Its result will show in the deliveries below.", flash[:notice]

    event = @webhook.deliveries.last.event
    assert_equal "webhook_tested", event.action
    assert_equal @webhook, event.eventable
    assert_equal "Leo", event.particulars["sent_by"]
  end

  test "the test is signed and carries the webhook in its envelope" do
    sign_in_as :leo
    sent = nil
    stub_request(:post, @webhook.url).with { |request| sent = request; true }.to_return(status: 200)

    post domain_webhook_test_path(@webhook.domain, @webhook)
    perform_enqueued_jobs

    assert_equal OpenSSL::HMAC.hexdigest("SHA256", @webhook.signing_secret, sent.body), sent.headers["X-Webhook-Signature"]
    body = JSON.parse(sent.body)
    assert_equal "webhook_tested", body["event"]
    assert_equal %w[ domain domain_id name sent_at sent_by url webhook_id ], body["payload"].keys.sort
    assert_equal @webhook.id, body["payload"]["webhook_id"]
    assert_equal "example.com", body["payload"]["domain"]
    assert_equal "Leo", body["payload"]["sent_by"]
    assert_equal 200, @webhook.deliveries.last.response[:code]
  end

  test "sends a test as JSON" do
    sign_in_as :leo

    assert_difference -> { @webhook.deliveries.count }, 1 do
      post domain_webhook_test_path(@webhook.domain, @webhook), as: :json
    end

    assert_response :created
    assert_equal @webhook.id, response.parsed_body["id"]
    assert_equal "webhook_tested", @webhook.deliveries.last.event.action
  end

  test "an inactive webhook takes no test as JSON" do
    sign_in_as :leo
    webhook = webhooks(:inactive)

    assert_no_difference -> { Webhook::Delivery.count } do
      post domain_webhook_test_path(webhook.domain, webhook), as: :json
    end

    assert_response :forbidden
  end

  test "the page offers a test on an active webhook" do
    sign_in_as :leo

    get domain_webhook_path(@webhook.domain, @webhook)

    assert_select "form[action=?] button", domain_webhook_test_path(@webhook.domain, @webhook), text: "Send a test"
  end

  test "an inactive webhook takes no test" do
    sign_in_as :leo
    webhook = webhooks(:inactive)

    get domain_webhook_path(webhook.domain, webhook)
    assert_select "form[action=?]", domain_webhook_test_path(webhook.domain, webhook), count: 0

    assert_no_difference -> { Webhook::Delivery.count } do
      post domain_webhook_test_path(webhook.domain, webhook)
    end
    assert_response :forbidden
  end

  test "an Action Mailbox relay webhook takes no test" do
    sign_in_as :leo
    webhook = domains(:example).webhooks.create!(name: "Relay",
      url: "https://example.com/rails/action_mailbox/relay/inbound_emails", subscribed_actions: %w[ inbound_email_received ])

    get domain_webhook_path(webhook.domain, webhook)
    assert_select "form[action=?]", domain_webhook_test_path(webhook.domain, webhook), count: 0

    assert_no_difference -> { Webhook::Delivery.count } do
      post domain_webhook_test_path(webhook.domain, webhook)
    end
    assert_response :forbidden
  end

  test "sending tests is rate limited by the minute" do
    sign_in_as :leo
    Rails.cache.stubs(:increment).returns(11)

    assert_no_difference -> { Webhook::Delivery.count } do
      post domain_webhook_test_path(@webhook.domain, @webhook)
    end

    assert_response :too_many_requests
  end

  test "a non-admin cannot send a test" do
    sign_in_as :nonstaff

    assert_no_difference -> { Webhook::Delivery.count } do
      post domain_webhook_test_path(@webhook.domain, @webhook)
    end

    assert_response :forbidden
  end

  test "cannot test another account's webhook" do
    sign_in_as :leo
    webhook = webhooks(:other_account)

    post domain_webhook_test_path(webhook.domain, webhook)

    assert_response :not_found
  end
end
