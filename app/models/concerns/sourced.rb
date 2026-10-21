module Sourced
  extend ActiveSupport::Concern

  MAX_ATTACHMENTS = 50

  included do
    has_one_attached :raw_email
    has_many_attached :attachments

    delegate :accessible_to?, to: :domain
  end

  class_methods do
    def purge_attachments(purgeable)
      attachments = ActiveStorage::Attachment.where(record_type: name, record_id: purgeable.select(:id))
      blob_ids = attachments.pluck(:blob_id)
      attachments.delete_all

      ActiveStorage::Blob.where(id: blob_ids).where.missing(:attachments).find_each(&:purge)
    end
  end

  def raw
    if raw_email.attached?
      @raw ||= raw_email.download
    end
  end

  def raw=(bytes)
    if bytes
      assign_source Source.new(bytes)
      raw_email.attach(io: StringIO.new(bytes), filename: "raw.eml", content_type: "message/rfc822")
    end
  end

  def source=(source)
    assign_source source
    raw_email.attach(source.blob)
  end

  def extract_attachments
    return if attachments.attached?

    parts = parsed_email.stored_attachments
    parts.first(MAX_ATTACHMENTS).each { |part| store_attachment(part) }
    log_dropped_attachments(parts.size - MAX_ATTACHMENTS) if parts.size > MAX_ATTACHMENTS
  end

  private
    def assign_source(source)
      @raw = source.raw
      @parsed_email = nil
      self.subject = source.subject
    end

    def store_attachment(part)
      attachments.attach(
        io: StringIO.new(part.bytes),
        filename: part.filename,
        content_type: part.content_type,
        identify: true,
        metadata: { "cid" => part.cid, "inline" => part.inline? }
      )
    end

    def log_dropped_attachments(count)
      Rails.logger.warn("Sourced: dropped #{count} attachment(s) past the #{MAX_ATTACHMENTS} cap on #{self.class.name} #{id}")
    end
end
