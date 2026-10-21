class IdempotentRequest < ApplicationRecord
  MAX_KEY_LENGTH = 255

  # Unsettled only if the process died mid-claim; ordinary failures clear it. Expire before the full dedupe window so stuck claims stop answering 451.
  ABANDONED_AFTER = 15.minutes

  belongs_to :sending_token
  belongs_to :message, optional: true

  validates :key, length: { maximum: MAX_KEY_LENGTH }

  Result = Struct.new(:status, :message)

  def self.fulfill(sending_token, key)
    claim = sending_token.idempotent_requests.create!(key:)
    begin
      message = yield
    rescue
      claim.destroy
      raise
    end
    claim.settle(message)
    Result.new(:fresh, message)
  rescue ActiveRecord::RecordNotUnique
    sending_token.idempotent_requests.find_by!(key:).result
  end

  def self.purge_old
    where(created_at: ...24.hours.ago).delete_all
    where(message_id: nil, created_at: ...ABANDONED_AFTER.ago).delete_all
  end

  def result
    if message
      Result.new(:replayed, message)
    else
      Result.new(:in_progress, nil)
    end
  end

  def settle(message)
    if message&.persisted?
      update! message: message
    else
      destroy
    end
  end
end
