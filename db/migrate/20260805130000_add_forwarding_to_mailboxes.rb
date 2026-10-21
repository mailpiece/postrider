class AddForwardingToMailboxes < ActiveRecord::Migration[8.2]
  def change
    add_column :mailboxes, :forward_to, :string, limit: 255
    add_column :mailboxes, :forward_confirmed_at, :datetime
    add_column :mailboxes, :forward_confirmation_code, :string, limit: 255
    add_column :mailboxes, :forward_confirmation_code_expires_at, :datetime
  end
end
