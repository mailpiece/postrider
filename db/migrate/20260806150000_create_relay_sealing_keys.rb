class CreateRelaySealingKeys < ActiveRecord::Migration[8.2]
  def change
    create_table :relay_sealing_keys, id: :uuid do |t|
      t.integer :singleton_guard, default: 0, null: false
      t.text :private_key, limit: 65535
      t.timestamps

      t.index :singleton_guard, unique: true
    end
  end
end
