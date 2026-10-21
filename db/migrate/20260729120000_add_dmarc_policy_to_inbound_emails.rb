class AddDmarcPolicyToInboundEmails < ActiveRecord::Migration[8.2]
  def change
    add_column :inbound_emails, :dmarc_policy, :string, limit: 255
  end
end
