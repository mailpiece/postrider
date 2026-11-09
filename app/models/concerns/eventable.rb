module Eventable
  extend ActiveSupport::Concern

  included do
    has_many :events, as: :eventable, dependent: :destroy
  end

  def track_event(action, eventable: self, **particulars)
    if should_track_event?
      Event.create!(eventable:, domain: eventable_domain, action: "#{eventable_prefix}_#{action}", particulars:)
    end
  end

  private
    def should_track_event?
      true
    end

    def eventable_prefix
      self.class.name.demodulize.underscore
    end

    def eventable_domain
      domain
    end
end
