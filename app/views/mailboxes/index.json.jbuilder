json.array! @page.records do |mailbox|
  json.id mailbox.id
  json.local_part mailbox.local_part
  json.domain mailbox.domain.name
end
