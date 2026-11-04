module Eventable
  extend ActiveSupport::Concern

  included do
    has_many :events, as: :eventable, dependent: :destroy
  end

  def track_event(action, **particulars)
    if should_track_event?
      Event.create!(eventable: self, domain: eventable_domain, action: "#{eventable_prefix}_#{action}", particulars:)
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
