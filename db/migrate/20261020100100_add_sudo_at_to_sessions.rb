class AddSudoAtToSessions < ActiveRecord::Migration[8.2]
  def change
    add_column :sessions, :sudo_at, :datetime
  end
end
