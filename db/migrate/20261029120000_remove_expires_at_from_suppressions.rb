class RemoveExpiresAtFromSuppressions < ActiveRecord::Migration[8.2]
  def change
    remove_column :suppressions, :expires_at, :datetime
  end
end
