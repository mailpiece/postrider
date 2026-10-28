class PacingSlot < ApplicationRecord
  # SQLite begins every transaction IMMEDIATE, so two workers never take the same slot.
  def self.reserve(provider, gap)
    transaction do
      slot = create_with(next_at: Time.current).create_or_find_by!(provider: provider)
      at = [ slot.next_at, Time.current ].max
      slot.update!(next_at: at + gap)
      at
    end
  end
end
