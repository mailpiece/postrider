cid = blob.metadata["cid"]

json.type "attachment"
json.filename blob.filename.to_s
json.contentType blob.content_type
json.size blob.byte_size
json.checksum blob.checksum
json.related true if blob.metadata["inline"]
if cid.present?
  json.cid cid
  json.contentId "<#{cid}>"
end
json.url rails_blob_url(blob, disposition: "attachment")
