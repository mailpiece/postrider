require "mailauth"

class Delivery::DkimSigning
  SIGNED_HEADERS = %w[
    from sender reply-to subject date message-id to cc
    mime-version content-type content-transfer-encoding
    in-reply-to references list-id list-help list-owner
    list-unsubscribe list-unsubscribe-post list-subscribe list-post
  ].freeze

  # Oversign so a header added after signing — even a first instance — breaks the signature.
  OVERSIGNED_HEADERS = %w[ from to cc subject date reply-to message-id ].freeze

  def self.sign(raw, domain:)
    MailAuth::Dkim.sign(raw,
      domain: domain.name, selector: domain.dkim_selector, key: domain.dkim_key,
      headers: SIGNED_HEADERS, oversign: OVERSIGNED_HEADERS)
  end
end
