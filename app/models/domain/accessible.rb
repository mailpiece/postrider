module Domain::Accessible
  extend ActiveSupport::Concern

  included do
    has_many :accesses, dependent: :delete_all do
      def revise(granted: [], revoked: [])
        transaction do
          grant_to granted
          revoke_from revoked
        end
      end

      def grant_to(users)
        Access.insert_all Array(users).collect { |user|
          { id: ActiveRecord::Type::Uuid.generate, domain_id: proxy_association.owner.id, user_id: user.id, account_id: proxy_association.owner.account_id }
        }
      end

      # Guarded here so callers can't revoke through an all_access domain.
      def revoke_from(users)
        destroy_by user: users unless proxy_association.owner.all_access?
      end
    end

    has_many :users, through: :accesses

    scope :all_access, -> { where(all_access: true) }

    after_create :grant_access_to_creator
    after_save_commit :grant_access_to_everyone
  end

  def accessible_to?(user)
    access_for(user).present?
  end

  def access_for(user)
    accesses.find_by(user: user)
  end

  private
    def grant_access_to_creator
      accesses.create(user: creator)
    end

    # Turning all_access off never revokes what it granted.
    def grant_access_to_everyone
      accesses.grant_to(account.users.active) if all_access_previously_changed?(to: true)
    end
end
