module Postable
  extend ActiveSupport::Concern

  included do
    has_one :mailpiece, as: :postable, dependent: :destroy

    scope :matching, ->(query) do
      where("subject LIKE ?", "%#{query}%")
        .or(where("mail_from LIKE ?", "%#{query}%"))
        .or(where("rcpt_to LIKE ?", "%#{query}%"))
    end

    after_create :establish_mailpiece, if: :should_establish_mailpiece?
    # Touch so the mail log etag moves with postable status changes.
    after_update_commit -> { mailpiece&.touch }
  end

  class_methods do
    def purge_mailpieces(scope)
      Mailpiece.where(postable_type: name, postable_id: scope.select(:id)).delete_all
    end
  end

  private
    def should_establish_mailpiece?
      true
    end

    def establish_mailpiece
      create_mailpiece!(domain:)
    end
end
