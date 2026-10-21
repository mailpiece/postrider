json.array! @page.records do |sending_token|
  json.id sending_token.id
  json.name sending_token.name
  json.domain sending_token.domain.name
end
