json.array! @page.records do |delivery|
  json.(delivery, :id, :state)
  json.created_at delivery.created_at.utc
  json.updated_at delivery.updated_at.utc

  json.request delivery.sanitized_request
  json.response delivery.response_summary

  json.event do
    json.(delivery.event, :id, :action)
    json.created_at delivery.event.created_at.utc
  end
end
