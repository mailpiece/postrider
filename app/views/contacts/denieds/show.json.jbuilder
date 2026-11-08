json.array! @page.records do |contact|
  json.partial! "contacts/contact", contact: contact
  json.held_count contact.held_inbound_emails.size
end
