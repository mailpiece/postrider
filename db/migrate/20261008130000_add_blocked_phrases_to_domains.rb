class AddBlockedPhrasesToDomains < ActiveRecord::Migration[8.2]
  def change
    add_column :domains, :blocked_phrases, :text, limit: 65535
  end
end
