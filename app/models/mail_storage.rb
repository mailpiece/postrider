class MailStorage
  def self.full?
    new.full?
  end

  def full?
    if limit = Relay.inbound_storage_limit
      bytes >= limit
    else
      false
    end
  end

  private
    def bytes
      Rails.cache.fetch("mail_storage_bytes", expires_in: 1.minute) { ActiveStorage::Blob.sum(:byte_size) }
    end
end
