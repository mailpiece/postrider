postable = mailpiece.postable

json.id mailpiece.id
json.direction mailpiece.inbound_email? ? "inbound" : "outbound"
json.subject mailpiece.subject
json.(postable, :mail_from, :rcpt_to, :status)
json.created_at mailpiece.created_at

if mailpiece.inbound_email?
  json.(postable, :forwarded_at, :spf, :dkim, :dmarc, :dmarc_policy, :arc)
end
