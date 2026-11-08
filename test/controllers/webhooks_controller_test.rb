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
    assert_select "##{dom_id webhooks(:active)} .row__end", count: 0
  end

  test "index says an admin turned a webhook off and offers to activate it" do
    webhook = webhooks(:active)
    webhook.deactivate

    get domain_webhooks_path(domains(:example))

    assert_select "##{dom_id webhook}" do
      assert_select ".row__meta", text: "Turned off webhook Deliveries · https://hooks.example.com/postrider"
      assert_select ".row__end form[action=?] button", domain_webhook_activation_path(domains(:example), webhook), text: "Activate"
    end
  end

  test "index says a webhook off since before its switches were recorded is inactive" do
    get domain_webhooks_path(domains(:example))

    assert_select "##{dom_id webhooks(:inactive)}" do
      assert_select ".row__meta", text: "Inactive · https://hooks.example.com/receipts"
      assert_select ".row__end form[action=?] button", domain_webhook_activation_path(domains(:example), webhooks(:inactive)), text: "Activate"
    end
  end

  test "index says why the tracker deactivated a webhook" do
    webhook = webhooks(:active)
    webhook.delinquency_tracker.update!(consecutive_failures_count: 9, first_failure_at: 2.hours.ago)
    webhook.delinquency_tracker.record_delivery_of(failed_delivery(webhook))

    get domain_webhooks_path(domains(:example))

    assert_select "##{dom_id webhook}" do
      assert_select ".row__meta", text: "Deactivated webhook after 10 failed deliveries · https://hooks.example.com/postrider"
      assert_select ".row__end form[action=?] button", domain_webhook_activation_path(domains(:example), webhook), text: "Activate"
    end
  end

  test "index says a webhook turned back on and off again by hand was turned off" do
    webhook = webhooks(:active)
    webhook.delinquency_tracker.update!(consecutive_failures_count: 9, first_failure_at: 2.hours.ago)
    webhook.delinquency_tracker.record_delivery_of(failed_delivery(webhook))
    webhook.activate
    webhook.deactivate

    get domain_webhooks_path(domains(:example))

    assert_select "##{dom_id webhook} .row__meta", text: "Turned off webhook Deliveries · https://hooks.example.com/postrider"
  end

  test "index reads every webhook's deactivation in one query" do
    webhooks(:active).delinquency_tracker.update!(consecutive_failures_count: 9, first_failure_at: 2.hours.ago)
    webhooks(:active).delinquency_tracker.record_delivery_of(failed_delivery(webhooks(:active)))
    3.times { |n| domains(:example).webhooks.create!(name: "Hook #{n}", url: "https://example.com/#{n}", active: false) }

    assert_queries_match(/FROM "events"/, count: 1) { get domain_webhooks_path(domains(:example)) }

    assert_select ".row__end form button", text: "Activate", count: 5
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
    assert_select "form[action=?] input[name=?][placeholder=?]", domain_webhooks_path(domains(:example)), "webhook[name]", "Name this webhook…"
    assert_select "label[for=webhook_url]", text: "Payload URL"
    assert_select "label[for=webhook_signing_secret]", text: /Signing secret/
    assert_select "input[type=password][name=?]:not([required])", "webhook[signing_secret]"
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
    assert_select "label[for=webhook_signing_secret]", text: /keep the current secret/
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

  test "show marks a delivery the endpoint turned down as failed" do
    webhook = webhooks(:active)
    event = Event.create!(account: Current.account, domain: domains(:example), action: "inbound_email_received", eventable: inbound_emails(:received))
    webhook.deliveries.create!(event: event, state: :completed, response: { code: 500 })

    get domain_webhook_path(domains(:example), webhook)

    assert_select ".trail__sentence .status--error", text: "Failed"
    assert_select ".trail__sentence", text: /Inbound mail received · Failed · HTTP 500/
  end

  test "show pages through every delivery" do
    webhook = webhooks(:active)
    event = Event.create!(domain: domains(:example), action: "inbound_email_received", eventable: inbound_emails(:received))
    25.times { webhook.deliveries.create!(event: event, state: :completed, response: { code: 200 }) }

    get domain_webhook_path(domains(:example), webhook)

    assert_select "[data-controller=pagination] .trail__entry", count: 15
    assert_select "a#deliveries-pagination-link-2"

    get domain_webhook_path(domains(:example), webhook, page: 2)

    assert_select "#deliveries-pagination-contents-2 .trail__entry", count: 10
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

  private
    def failed_delivery(webhook)
      webhook.deliveries.create!(event: deliveries(:delivered).track_event("delivered"), state: :completed, response: { code: 500 })
    end
end
