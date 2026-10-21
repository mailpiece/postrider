json.partial! "contacts/contact", contact: @contact
json.emails @page.records do |mailpiece|
  json.(mailpiece, :id, :subject)
  json.mail_from mailpiece.postable.mail_from
  json.rcpt_to mailpiece.postable.rcpt_to
  json.received_at mailpiece.created_at.utc
end
