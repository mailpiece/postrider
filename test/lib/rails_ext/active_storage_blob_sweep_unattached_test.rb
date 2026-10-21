require "test_helper"

class ActiveStorageBlobSweepUnattachedTest < ActiveSupport::TestCase
  test "purges unattached blobs older than two days, keeping fresh and attached ones" do
    stale = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("stale"), filename: "stale.eml", content_type: "message/rfc822")
    stale.update_column(:created_at, 3.days.ago)

    fresh = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("fresh"), filename: "fresh.eml", content_type: "message/rfc822")

    attached = messages(:queued)
    attached.raw = file_fixture("raw.eml").read
    attached.raw_email.blob.update_column(:created_at, 3.days.ago)

    perform_enqueued_jobs only: ActiveStorage::PurgeJob do
      ActiveStorage::Blob.sweep_unattached
    end

    assert_not ActiveStorage::Blob.exists?(stale.id)
    assert ActiveStorage::Blob.exists?(fresh.id)
    assert attached.reload.raw_email.attached?
  end
end
