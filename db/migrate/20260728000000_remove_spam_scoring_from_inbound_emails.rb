class RemoveSpamScoringFromInboundEmails < ActiveRecord::Migration[8.2]
  def change
    remove_column :inbound_emails, :spam_score, :float
    remove_column :inbound_emails, :spam_action, :string, limit: 255
  end
end
