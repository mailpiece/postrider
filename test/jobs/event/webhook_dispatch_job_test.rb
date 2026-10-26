require "test_helper"

class Event::WebhookDispatchJobTest < ActiveJob::TestCase
  setup do
    @domain = domains(:example)
    @event = deliveries(:delivered).track_event("delivered")
  end

  test "delivers to a webhook in the event's account" do
    webhook = create_webhook(account: @domain.account)

    Event::WebhookDispatchJob.perform_now(@event)

    assert_equal [ @event ], webhook.deliveries.map(&:event)
  end

  test "does not deliver to a webhook in another account that points at the event's domain" do
    foreign_webhook = create_webhook(account: accounts(:other_account))

    Event::WebhookDispatchJob.perform_now(@event)

    assert_empty foreign_webhook.deliveries
  end

  private
    def create_webhook(account:)
      Webhook.create!(account: account, domain: @domain, name: "Webhook", url: "https://example.com/webhook", subscribed_actions: [ "delivery_delivered" ])
    end
end
