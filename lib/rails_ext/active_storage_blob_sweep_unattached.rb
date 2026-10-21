ActiveSupport.on_load :active_storage_blob do
  def self.sweep_unattached
    unattached.where(created_at: ...2.days.ago).find_each(&:purge_later)
  end
end
