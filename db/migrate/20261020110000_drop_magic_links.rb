class DropMagicLinks < ActiveRecord::Migration[8.2]
  def change
    drop_table :magic_links, id: :uuid do |t|
      t.uuid :identity_id
      t.string :code, limit: 255, null: false
      t.integer :purpose, null: false
      t.datetime :expires_at, null: false

      t.timestamps

      t.index :code, unique: true
      t.index :expires_at
      t.index :identity_id
    end
  end
end
