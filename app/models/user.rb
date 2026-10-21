class User < ApplicationRecord
  include Accessor, Configurable, Named, Role

  belongs_to :account
  belongs_to :identity, optional: true

  validates :name, presence: true

  def deactivate
    transaction do
      update! active: false, identity: nil
      close_remote_connections
    end
  end

  def setup?
    name != identity.email_address
  end

  def verified?
    verified_at.present?
  end

  def verify
    update!(verified_at: Time.current) unless verified?
  end

  private
    def close_remote_connections
      ActionCable.server.remote_connections.where(current_user: self).disconnect(reconnect: false)
    end
end
