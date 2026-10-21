require "test_helper"

class WebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :leo
  end

  test "index renders, including existing webhooks" do
    get domain_webhooks_path(domains(:example))

    assert_response :success
    assert_select "[data-controller=pagination][data-pagination-paginate-on-intersection-value=true]"
    assert_select "input[placeholder=?]", "Filter webhooks…"
    assert_select ".filter__empty a", count: 0
    assert_select "li.row[data-quick-find-target=item]"
    assert_select "a.row__body .row__title", text: "Deliveries"
    assert_select "a.row__body .row__meta", text: "Active · https://hooks.example.com/postrider"
    assert_select ".row__end", count: 0
  end

  test "new renders" do
    confirm_sudo

    get new_domain_webhook_path(domains(:example))

    assert_response :success
    assert_select "form[action=?] input[name=?][placeholder=?]", domain_webhooks_path(domains(:example)), "webhook[name]", "Name this webhook…"
    assert_select "label[for=webhook_url]", text: "Payload URL"
    assert_select "[data-controller=toggle-class] input.switch__input[data-toggle-class-target=checkbox]", count: Webhook::PERMITTED_ACTIONS.size
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

  test "show marks a delivery the endpoint turned down as failed" do
    webhook = webhooks(:active)
    event = Event.create!(account: Current.account, domain: domains(:example), action: "inbound_email_received", eventable: inbound_emails(:received))
    webhook.deliveries.create!(event: event, state: :completed, response: { code: 500 })

    get domain_webhook_path(domains(:example), webhook)

    assert_select ".trail__sentence .status--error", text: "Failed"
    assert_select ".trail__sentence", text: /Inbound mail received · Failed · HTTP 500/
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
