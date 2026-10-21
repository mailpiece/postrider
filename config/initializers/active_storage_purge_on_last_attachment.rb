# Default AS purge uses delete (skips callbacks) and can drop blobs still referenced
# elsewhere; destroy and only purge when this was the last attachment.
module ActiveStorage
  module PurgeOnLastAttachment
    def purge
      @purge_mode = :purge
      destroy
      purge_blob_if_last(:purge) if destroyed?
    ensure
      @purge_mode = nil
    end

    def purge_later
      @purge_mode = :purge_later
      destroy
      purge_blob_if_last(:purge_later) if destroyed?
    ensure
      @purge_mode = nil
    end

    private
      # Tracks Rails' callback name, renamed from `purge_dependent_blob_later` when it grew
      # the dependent: :purge branch. Skips when purge/purge_later is already driving the blob.
      def purge_dependent_blob
        return if @purge_mode

        # `record.nil?` first: `dependent` reads `record.attachment_reflections`, so an orphaned
        # attachment can't evaluate it and falls back to purge_later.
        if record.nil? || dependent == :purge_later
          purge_blob_if_last(:purge_later)
        elsif dependent == :purge
          purge_blob_if_last(:purge)
        end
      end

      def purge_blob_if_last(mode)
        if blob && !blob.attachments.exists?
          mode == :purge ? blob.purge : blob.purge_later
        end
      end
  end
end

ActiveSupport.on_load(:active_storage_attachment) do
  prepend ActiveStorage::PurgeOnLastAttachment
end
