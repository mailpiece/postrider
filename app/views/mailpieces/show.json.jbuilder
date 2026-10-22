json.id @mailpiece.id
json.direction @mailpiece.inbound_email? ? "inbound" : "outbound"
json.(@postable, :mail_from, :rcpt_to, :status, :created_at)

json.partial! "mailpieces/content", postable: @postable

if @mailpiece.inbound_email?
  json.(@postable, :forwarded_at, :spf, :dkim, :dmarc, :dmarc_policy, :arc, :arc_sealer, :iprev, :remote_host,
    :from_aligned, :authentication_results)
  json.incinerated_at @postable.incinerated_at if @postable.incinerated?
else
  json.incinerated_at @postable.message.incinerated_at if @postable.message.incinerated?

  json.attempts @postable.attempts.order(:created_at) do |attempt|
    json.(attempt, :mx_host, :code, :output, :created_at)
  end

  json.events @postable.events.ordered do |event|
    json.action event.action
    json.particulars event.particulars_for(Current.user)
    json.created_at event.created_at
  end
end
