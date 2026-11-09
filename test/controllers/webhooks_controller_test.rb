require "test_helper"

class WebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :leo
  end

  test "index lists the webhooks" do
    get domain_webhooks_path(domains(:example))

    assert_response :success
    assert_select ".row__title", text: "Deliveries"
  end

  test "index offers to activate a webhook an admin turned off" do
    webhook = webhooks(:active)
    webhook.deactivate

    get domain_webhooks_path(domains(:example))

    assert_select "form[action=?] button", domain_webhook_activation_path(domains(:example), webhook), text: "Activate"
  end

  test "index offers to activate a webhook off since before its switches were recorded" do
    get domain_webhooks_path(domains(:example))

    assert_select "form[action=?] button", domain_webhook_activation_path(domains(:example), webhooks(:inactive)), text: "Activate"
  end

  test "activating a webhook from the list returns to it" do
    webhook = webhooks(:inactive)

    post domain_webhook_activation_path(domains(:example), webhook), headers: { "HTTP_REFERER" => domain_webhooks_url(domains(:example)) }

    assert_redirected_to domain_webhooks_url(domains(:example))
    assert webhook.reload.active?
  end

  test "new renders" do
    confirm_sudo

    get new_domain_webhook_path(domains(:example))

    assert_response :success
    assert_select "form[action=?]", domain_webhooks_path(domains(:example))
  end

  test "creates a webhook" do
    confirm_sudo

    assert_difference -> { domains(:example).webhooks.count }, 1 do
      post domain_webhooks_path(domains(:example)),
        params: { webhook: { name: "Hooky", url: "https://example.com/h", subscribed_actions: %w[ inbound_email_received ] } }
    end
    assert_response :redirect
    assert_equal "Webhook added", flash[:notice]
  end

  test "creates a webhook with the signing secret given" do
    confirm_sudo

    post domain_webhooks_path(domains(:example)),
      params: { webhook: { name: "Hooky", url: "https://example.com/h", signing_secret: "a-secret-of-our-own", subscribed_actions: %w[ inbound_email_received ] } }

    assert_response :redirect
    assert_equal "a-secret-of-our-own", domains(:example).webhooks.find_by!(name: "Hooky").signing_secret
  end

  test "creating a webhook with invalid attributes re-renders the form with its errors" do
    confirm_sudo

    assert_no_difference -> { domains(:example).webhooks.count } do
      post domain_webhooks_path(domains(:example)), params: { webhook: { name: "", url: "not-a-url", subscribed_actions: %w[ inbound_email_received ] } }
    end

    assert_response :unprocessable_entity
    assert_select ".error-explanation__message", minimum: 1
  end

  test "creating a webhook to an Action Mailbox relay with an outbound event says why it is refused" do
    confirm_sudo

    post domain_webhooks_path(domains(:example)), params: { webhook: { name: "Relay",
      url: "https://example.com/rails/action_mailbox/relay/inbound_emails", subscribed_actions: %w[ delivery_delivered ] } }

    assert_response :unprocessable_entity
    assert_select ".error-explanation__message", text: /Action Mailbox relay/
  end

  test "updating a webhook to an Action Mailbox relay with an outbound event says why it is refused" do
    confirm_sudo

    webhook = domains(:example).webhooks.create!(name: "Relay",
      url: "https://example.com/rails/action_mailbox/relay/inbound_emails", subscribed_actions: %w[ inbound_email_received ])

    patch domain_webhook_path(domains(:example), webhook), params: { webhook: { name: "Relay", subscribed_actions: %w[ delivery_delivered ] } }

    assert_response :unprocessable_entity
    assert_select ".error-explanation__message", text: /Action Mailbox relay/
  end

  test "updates a webhook" do
    confirm_sudo

    webhook = webhooks(:active)

    patch domain_webhook_path(domains(:example), webhook), params: { webhook: { name: "Renamed", subscribed_actions: %w[ inbound_email_received ] } }

    assert_redirected_to domain_webhook_path(domains(:example), webhook)
    assert_equal "Webhook updated", flash[:notice]
    assert_equal "Renamed", webhook.reload.name
  end

  test "edit renders a blank, optional signing secret field" do
    confirm_sudo

    get edit_domain_webhook_path(domains(:example), webhooks(:active))

    assert_response :success
    assert_select "input[type=password][name=?]:not([required])", "webhook[signing_secret]"
  end

  test "updating a webhook changes its signing secret" do
    confirm_sudo

    webhook = webhooks(:active)

    patch domain_webhook_path(domains(:example), webhook), params: { webhook: { name: "Renamed", signing_secret: "a-rotated-relay-password" } }

    assert_redirected_to domain_webhook_path(domains(:example), webhook)
    assert_equal "a-rotated-relay-password", webhook.reload.signing_secret
  end

  test "updating a webhook with a blank signing secret keeps the current one" do
    confirm_sudo

    webhook = webhooks(:active)

    patch domain_webhook_path(domains(:example), webhook), params: { webhook: { name: "Renamed", signing_secret: "" } }

    assert_redirected_to domain_webhook_path(domains(:example), webhook)
    assert_equal "Renamed", webhook.reload.name
    assert_equal "Wc4oqgMXpZGK8vYbJhT3sN2d", webhook.signing_secret
  end

  test "updating a webhook's signing secret over json" do
    confirm_sudo

    webhook = webhooks(:active)

    patch domain_webhook_path(domains(:example), webhook), params: { webhook: { signing_secret: "a-rotated-relay-password" } }, as: :json

    assert_response :success
    assert_equal "a-rotated-relay-password", response.parsed_body["signing_secret"]
  end

  test "updating a webhook with a short signing secret re-renders the form with its errors" do
    confirm_sudo

    webhook = webhooks(:active)

    patch domain_webhook_path(domains(:example), webhook), params: { webhook: { signing_secret: "too-short" } }

    assert_response :unprocessable_entity
    assert_select ".error-explanation__message", text: /too short/
    assert_equal "Wc4oqgMXpZGK8vYbJhT3sN2d", webhook.reload.signing_secret
  end

  test "creating a webhook in the browser asks for a passkey first" do
    assert_no_difference -> { domains(:example).webhooks.count } do
      post domain_webhooks_path(domains(:example)), params: { webhook: { name: "Hooky", url: "https://example.com/h", subscribed_actions: %w[ inbound_email_received ] } }
    end

    assert_redirected_to new_my_sudo_path
  end

  test "deletes a webhook" do
    webhook = webhooks(:active)

    assert_difference -> { domains(:example).webhooks.count }, -1 do
      delete domain_webhook_path(domains(:example), webhook)
    end

    assert_redirected_to domain_webhooks_path(domains(:example))
    assert_equal "Webhook deleted", flash[:notice]
  end

  test "activates and deactivates a webhook" do
    webhook = webhooks(:active)

    delete domain_webhook_activation_path(domains(:example), webhook)
    assert_equal "Webhook deactivated", flash[:notice]
    assert_not webhook.reload.active?

    post domain_webhook_activation_path(domains(:example), webhook)
    assert_equal "Webhook activated", flash[:notice]
    assert webhook.reload.active?
  end

  test "show renders the webhook and its recent deliveries" do
    webhook = webhooks(:active)
    event = Event.create!(account: Current.account, domain: domains(:example), action: "inbound_email_received", eventable: inbound_emails(:received))
    webhook.deliveries.create!(event: event, state: :completed, response: { code: 200 })

    get domain_webhook_path(domains(:example), webhook)

    assert_response :success
    assert_select "code", text: webhook.signing_secret
    assert_select ".trail__sentence", text: /Inbound mail received · Completed · HTTP 200/
  end

  test "show pages through every delivery" do
    webhook = webhooks(:active)
    event = Event.create!(domain: domains(:example), action: "inbound_email_received", eventable: inbound_emails(:received))
    25.times { webhook.deliveries.create!(event: event, state: :completed, response: { code: 200 }) }

    get domain_webhook_path(domains(:example), webhook)

    assert_select "a#deliveries-pagination-link-2"

    get domain_webhook_path(domains(:example), webhook, page: 2)

    assert_select "a#deliveries-pagination-link-3", count: 0
  end

  test "show json carries no pagination" do
    get domain_webhook_path(domains(:example), webhooks(:active)), as: :json

    assert_response :success
    assert_equal webhooks(:active).id, response.parsed_body["id"]
    assert_nil response.headers["X-Total-Count"]
  end

  test "index json" do
    get domain_webhooks_path(domains(:example)), as: :json

    assert_response :success
    assert_includes response.parsed_body.map { |row| row["id"] }, webhooks(:active).id
  end

  test "show is not found for another account's webhook" do
    get domain_webhook_path(domains(:example), webhooks(:other_account))

    assert_response :not_found
  end
end
