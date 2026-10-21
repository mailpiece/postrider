class InboundEmail::Payload
  def initialize(inbound_email)
    @inbound_email = inbound_email
    @content = Mailpiece::Content.new(inbound_email)
  end

  def to_h
    if @content.parsed?
      compact @content.to_h.merge(identity).merge(authentication).merge(attachments).merge(dmarc_report)
    else
      compact identity.merge(from: @inbound_email.mail_from)
    end
  end

  private
    def identity
      { id: @inbound_email.mailpiece&.id, rcpt_to: @inbound_email.rcpt_to }
    end

    def authentication
      { authentication: verdicts.presence&.merge(from_aligned: @inbound_email.from_aligned) }
    end

    def verdicts
      compact(spf: @inbound_email.spf, dkim: @inbound_email.dkim, dmarc: @inbound_email.dmarc,
        dmarc_policy: @inbound_email.dmarc_policy, arc: @inbound_email.arc,
        arc_sealer: @inbound_email.arc_sealer, authentication_results: @inbound_email.authentication_results)
    end

    def attachments
      blobs = @inbound_email.attachments.blobs

      if blobs.any?
        { attachments: blobs.map { |blob| attachment_hash(blob) } }
      else
        {}
      end
    end

    def attachment_hash(blob)
      cid = blob.metadata["cid"]

      compact({
        type: "attachment",
        contentType: blob.content_type,
        filename: blob.filename.to_s,
        size: blob.byte_size,
        checksum: blob.checksum,
        contentId: cid.presence && "<#{cid}>",
        cid: cid,
        related: blob.metadata["inline"],
        url: Rails.application.routes.url_helpers.rails_blob_url(blob, disposition: "attachment",
          script_name: @inbound_email.account.slug)
      })
    end

    def dmarc_report
      { dmarc_report: deep_h(@inbound_email.dmarc_report) }
    end

    # Data#to_h is shallow; walk nested Data/arrays for JSON-friendly hashes.
    def deep_h(value)
      case value
      when Data then value.to_h.transform_values { |member| deep_h(member) }
      when Array then value.map { |member| deep_h(member) }
      when Range then { begin: deep_h(value.begin), end: deep_h(value.end) }
      else value
      end
    end

    def compact(hash)
      hash.reject { |_, value| value.blank? }
    end
end
