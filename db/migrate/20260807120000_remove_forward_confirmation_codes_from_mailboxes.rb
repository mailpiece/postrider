class RemoveForwardConfirmationCodesFromMailboxes < ActiveRecord::Migration[8.2]
  def change
    remove_column :mailboxes, :forward_confirmation_code, :string, limit: 255
    remove_column :mailboxes, :forward_confirmation_code_expires_at, :datetime
  end
end
