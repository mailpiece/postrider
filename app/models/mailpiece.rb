class Mailpiece < ApplicationRecord
  belongs_to :account, default: -> { domain.account }
  belongs_to :domain

  delegated_type :postable, types: %w[ InboundEmail Delivery ]

  delegate :subject, to: :postable

  scope :ordered, -> { order(created_at: :desc) }
  scope :preloaded, -> { includes(:postable) }
  scope :inbound, -> { where(postable_type: "InboundEmail") }
  scope :outbound, -> { where(postable_type: "Delivery") }
  scope :matching, ->(query) do
    inbound.where(postable_id: InboundEmail.matching(query).select(:id))
      .or(outbound.where(postable_id: Delivery.matching(query).select(:id)))
  end
  scope :held, -> { inbound.where(postable_id: InboundEmail.held.select(:id)) }
  scope :deferred, -> { outbound.where(postable_id: Delivery.deferred.select(:id)) }
  scope :discarded, -> { inbound.where(postable_id: InboundEmail.bounced.select(:id)) }
  scope :withheld, -> { outbound.where(postable_id: Delivery.withheld.select(:id)) }
  scope :queued, -> do
    outbound.where(postable_id: Delivery.queued.select(:id))
      .or(inbound.where(postable_id: InboundEmail.in_flight.select(:id)))
  end
  scope :delivered, -> do
    outbound.where(postable_id: Delivery.delivered.select(:id))
      .or(inbound.where(postable_id: InboundEmail.delivered.select(:id)))
  end
  scope :failed, -> do
    outbound.where(postable_id: Delivery.failed.select(:id))
      .or(inbound.where(postable_id: InboundEmail.failed.select(:id)))
  end
end
