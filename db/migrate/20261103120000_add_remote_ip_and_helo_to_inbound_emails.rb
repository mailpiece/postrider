class AddRemoteIpAndHeloToInboundEmails < ActiveRecord::Migration[8.2]
  def change
    add_column :inbound_emails, :remote_ip, :string, limit: 255
    add_column :inbound_emails, :helo, :string, limit: 255
  end
end
