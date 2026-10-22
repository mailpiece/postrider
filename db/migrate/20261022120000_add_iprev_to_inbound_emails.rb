class AddIprevToInboundEmails < ActiveRecord::Migration[8.2]
  def change
    add_column :inbound_emails, :iprev, :string, limit: 255
    add_column :inbound_emails, :remote_host, :string, limit: 255
  end
end
