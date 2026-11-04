json.array! @page.records do |contact|
  json.partial! "contacts/contact", contact: contact
  json.held_count contact.inbound_emails.held.count
end
