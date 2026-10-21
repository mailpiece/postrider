class ParsedEmail::Attachment
  def initialize(part, referenced_cids = [])
    @part = part
    @referenced_cids = referenced_cids
  end

  def filename
    @part.filename.presence || "attachment"
  end

  def content_type
    @part.mime_type
  end

  def cid
    @part.content_id&.delete("<>").presence
  end

  def inline?
    cid.present? && (disposition_inline? || referenced_in_body?)
  end

  def bytes
    @part.body.decoded
  end

  private
    # Not Mail::Part#inline? — a whole message standing in for a part doesn't answer that.
    def disposition_inline?
      @part.header[:content_disposition]&.disposition_type&.casecmp?("inline")
    end

    def referenced_in_body?
      @referenced_cids.include?(cid)
    end
end
