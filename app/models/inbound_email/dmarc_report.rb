class InboundEmail::DmarcReport
  # RFC 7489 §7.2.1.1 sends a report as XML, gzip or zip.
  REPORT_TYPE = /xml|gzip|zip/i
  REPORT_NAME = /\.(xml|gz|zip)\z/i
  MAX_TRIES = 3

  def self.for(inbound_email)
    new(inbound_email).report
  end

  def initialize(inbound_email)
    @inbound_email = inbound_email
  end

  def report
    if @inbound_email.to_dmarc_reports_address?
      report_blobs.lazy.filter_map { |blob| MailReport::Dmarc.parse(blob.download) }.first
    end
  end

  private
    def report_blobs
      @inbound_email.attachments_blobs.select { |blob| report_like?(blob) }.first(MAX_TRIES)
    end

    def report_like?(blob)
      blob.content_type.to_s.match?(REPORT_TYPE) || blob.filename.to_s.match?(REPORT_NAME)
    end
end
