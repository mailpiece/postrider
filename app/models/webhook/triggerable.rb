module Webhook::Triggerable
  extend ActiveSupport::Concern

  included do
    scope :triggered_by, ->(event) { where(domain: event.domain).triggered_by_action(event.action) }
    scope :triggered_by_action, ->(action) { where("subscribed_actions LIKE ?", "%\"#{action}\"%") }
  end

  def trigger(event)
    deliveries.create_or_find_by!(event:) unless account.cancelled?
  end
end
