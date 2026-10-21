class CreatePauses < ActiveRecord::Migration[8.2]
  def change
    create_table :pauses, id: :uuid do |t|
      t.string :recipient_domain, limit: 255, null: false
      t.text :smtp_output, limit: 65535
      t.uuid :delivery_id

      t.timestamps

      t.index :recipient_domain, unique: true
      t.index :delivery_id
    end
  end
end
