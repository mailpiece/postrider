module User::Accessor
  extend ActiveSupport::Concern

  included do
    has_many :accesses, dependent: :destroy
    has_many :domains, through: :accesses
    has_many :accessible_messages, through: :domains, source: :messages
    has_many :accessible_deliveries, through: :domains, source: :deliveries
    has_many :accessible_inbound_emails, through: :domains, source: :inbound_emails
    has_many :accessible_events, through: :domains, source: :events
    has_many :accessible_suppressions, through: :domains, source: :suppressions
    has_many :accessible_mailpieces, through: :domains, source: :mailpieces
    has_many :accessible_contacts, through: :domains, source: :contacts

    after_create_commit :grant_access_to_domains, unless: :system?
  end

  private
    def grant_access_to_domains
      Access.insert_all account.domains.all_access.ids.collect { |domain_id|
        { id: ActiveRecord::Type::Uuid.generate, domain_id: domain_id, user_id: id, account_id: account_id }
      }
    end
end
