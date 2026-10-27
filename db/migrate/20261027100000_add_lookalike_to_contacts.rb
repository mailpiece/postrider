class AddLookalikeToContacts < ActiveRecord::Migration[8.2]
  def change
    add_column :contacts, :lookalike, :boolean, default: false, null: false
  end
end
