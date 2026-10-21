class AddArcToInboundEmails < ActiveRecord::Migration[8.2]
  def change
    add_column :inbound_emails, :arc, :string, limit: 255
    add_column :inbound_emails, :arc_sealer, :string, limit: 255
  end
end
