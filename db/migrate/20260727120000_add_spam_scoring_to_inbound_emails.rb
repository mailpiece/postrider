class AddSpamScoringToInboundEmails < ActiveRecord::Migration[8.2]
  def change
    add_column :inbound_emails, :spam_score, :float
    add_column :inbound_emails, :spam_action, :string, limit: 255
  end
end
