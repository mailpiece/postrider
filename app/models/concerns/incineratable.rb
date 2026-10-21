module Incineratable
  extend ActiveSupport::Concern

  included do
    has_one :incineration, as: :incinerable, dependent: :destroy

    scope :incinerated,   -> { joins(:incineration) }
    scope :incineratable, -> { where.missing(:incineration) }
  end

  class_methods do
    def incinerate_all_due
      due_for_incineration.find_each(&:incinerate)
    end
  end

  def incinerate
    unless incinerated?
      transaction do
        create_incineration!
        track_event "incinerated"
        self.class.purge_attachments(self.class.where(id: id))
      end
    end
  end

  def incinerated?
    incineration.present?
  end

  def incinerated_at
    incineration&.created_at
  end
end
