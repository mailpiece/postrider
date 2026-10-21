class AddOriginToMessages < ActiveRecord::Migration[8.2]
  def change
    add_column :messages, :origin, :string, limit: 255, default: "submitted", null: false
  end
end
