class IndexMessagesOnDomainIdAndMailMessageId < ActiveRecord::Migration[8.2]
  def change
    remove_index :messages, :domain_id
    add_index :messages, [ :domain_id, :mail_message_id ]
  end
end
