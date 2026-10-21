# Skip AnalyzeJob when the upload was deleted before analysis (avoids NoSuchKey).
module ActiveStorageAnalyzeJobSkipDetached
  def perform(blob)
    return unless blob.attachments.exists?

    super
  end
end

ActiveSupport.on_load :active_storage_blob do
  ActiveStorage::AnalyzeJob.prepend ActiveStorageAnalyzeJobSkipDetached
end
