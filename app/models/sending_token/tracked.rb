module SendingToken::Tracked
  extend ActiveSupport::Concern

  included do
    after_create_commit :track_creation
    after_destroy_commit :track_revocation, unless: :destroyed_by_association
  end

  private
    def track_creation
      track_domain_event "created"
    end

    def track_revocation
      track_domain_event "revoked"
    end

    # On the domain, so the trail keeps a token's events after it is deleted.
    def track_domain_event(action, **particulars)
      Event.create!(eventable: domain, domain: domain, action: "sending_token_#{action}", particulars: { token_name: name, **particulars })
    end
end
