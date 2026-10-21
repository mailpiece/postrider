class InboundEmail::DmarcReport
  def self.for(inbound_email)
    new(inbound_email).report
  end

  def initialize(inbound_email)
    @inbound_email = inbound_email
  end

  def report
    if @inbound_email.to_dmarc_reports_address?
      @inbound_email.attachments_blobs.lazy.filter_map { |blob| MailReport::Dmarc.parse(blob.download) }.first
    end
  end
end
