module Eventable
  extend ActiveSupport::Concern

  included do
    has_many :events, as: :eventable, dependent: :destroy
  end

  # Via Event.create, not events association — Domain names its ownership has_many :events.
  def track_event(action, **particulars)
    if should_track_event?
      Event.create!(eventable: self, domain: eventable_domain, action: "#{eventable_prefix}_#{action}", particulars: scrub(particulars))
    end
  end

  private
    def should_track_event?
      true
    end

    def eventable_prefix
      self.class.name.demodulize.underscore
    end

    # Domain overrides this.
    def eventable_domain
      domain
    end

    def scrub(particulars)
      particulars.transform_values do |value|
        value.is_a?(String) ? value.dup.force_encoding(Encoding::UTF_8).scrub : value
      end
    end
end
