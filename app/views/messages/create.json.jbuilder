json.id @message.id
json.status "queued"
json.message_id @message.mail_message_id
json.recipients @message.deliveries.pluck(:rcpt_to)
json.submitted_at @message.created_at.iso8601
