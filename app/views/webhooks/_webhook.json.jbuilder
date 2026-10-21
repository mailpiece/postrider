json.(webhook, :id, :name, :active, :signing_secret, :subscribed_actions)
json.payload_url webhook.url
json.created_at webhook.created_at.utc
json.url domain_webhook_url(webhook.domain, webhook)
