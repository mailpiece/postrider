class AddEndsAtToPauses < ActiveRecord::Migration[8.2]
  def change
    add_column :pauses, :ends_at, :datetime
  end
end
