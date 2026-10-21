json.mailpieces @page.records do |mailpiece|
  json.id mailpiece.id
  json.direction mailpiece.inbound_email? ? "inbound" : "outbound"
  json.subject mailpiece.subject
  json.(mailpiece.postable, :mail_from, :rcpt_to, :status)
  json.created_at mailpiece.created_at
end
json.contacts @contacts, partial: "contacts/contact", as: :contact
json.domains @domains, partial: "domains/domain", as: :domain
