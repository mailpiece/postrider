class AddAcmeChallengeRecordsToRelayCertificates < ActiveRecord::Migration[8.2]
  def change
    add_column :relay_certificates, :acme_challenge_records, :json
  end
end
