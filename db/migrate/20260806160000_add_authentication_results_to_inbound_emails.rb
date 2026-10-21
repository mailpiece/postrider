class AddAuthenticationResultsToInboundEmails < ActiveRecord::Migration[8.2]
  def change
    add_column :inbound_emails, :authentication_results, :text, limit: 65535
  end
end
