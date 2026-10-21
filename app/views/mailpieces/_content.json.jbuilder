if postable.raw_email.attached?
  json.raw_url rails_blob_url(postable.raw_email, disposition: "attachment")
  json.attachments postable.attachments.blobs, partial: "mailpieces/attachment", as: :blob
  json.merge! Mailpiece::Content.new(postable).to_h
else
  json.attachments []
end
