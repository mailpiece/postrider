class AddExpiresAtToSuppressions < ActiveRecord::Migration[8.2]
  def up
    add_column :suppressions, :expires_at, :datetime

    # Every existing row was written by a classifier that suppressed on any 5xx,
    # so most of them name addresses nothing is wrong with. Dating them from
    # creation retires the mistakes without discarding the record of them.
    execute "UPDATE suppressions SET expires_at = datetime(created_at, '+30 days')"
  end

  def down
    remove_column :suppressions, :expires_at
  end
end
