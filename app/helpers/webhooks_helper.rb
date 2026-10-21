module WebhooksHelper
  ACTION_LABELS = {
    "inbound_email_received" => "Inbound mail received",
    "inbound_email_bounce_received" => "Inbound bounce (DSN) mail",
    "inbound_email_forwarded" => "Inbound mail forwarded on",
    "delivery_delivered" => "Outbound message delivered",
    "delivery_deferred" => "Outbound delivery deferred",
    "delivery_failed" => "Outbound delivery failed",
    "delivery_bounced" => "Outbound bounce reported",
    "recipient_domain_paused" => "Recipient domain paused",
    "recipient_domain_resumed" => "Recipient domain resumed",
    "sending_token_created" => "Sending token created",
    "sending_token_revoked" => "Sending token revoked",
    "sending_token_refused" => "Sending token refused"
  }.freeze

  def webhook_action_options(actions = Webhook::PERMITTED_ACTIONS)
    ACTION_LABELS.select { |key, _| actions.include?(key) }
  end

  def webhook_action_label(action)
    ACTION_LABELS[action] || action.to_s.humanize
  end

  def active_tag(webhook, form: :word)
    if webhook.active?
      tag.span "Active", class: class_names("status status--success", StatusHelper::STATUS_FORMS.fetch(form))
    else
      tag.span "Inactive", class: class_names("status status--muted", StatusHelper::STATUS_FORMS.fetch(form))
    end
  end

  def webhook_delivery_status_tag(delivery)
    status_tag delivery.failed? ? "failed" : delivery.state
  end

  def webhook_delivery_snippet(delivery)
    if summary = delivery.response_summary
      if summary[:code]
        "HTTP #{summary[:code]}"
      elsif summary[:error]
        summary[:error].to_s.humanize
      end
    end
  end
end
