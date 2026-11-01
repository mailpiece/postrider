json.name @domain.name
json.verified @domain.verified?
json.checked_at @domain.dns_checked_at&.utc

json.records @domain.dns_listings do |listing|
  json.title listing.title
  json.type listing.record.type
  json.name listing.record.hostname
  json.value listing.record.value
  json.status listing.status
  json.error listing.error
end
