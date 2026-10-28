# Webhooks

Webhooks are how PostRider tells your app what's happening to your mail — the moment a message arrives, lands, or bounces. Point one or more HTTPS endpoints at your app, one domain at a time, from each domain's **Webhooks** page in the admin UI. A webhook only ever hears about its own domain's events. Each webhook has:

- Subscribed event types (see below)
- A per-webhook **signing secret** (HMAC-SHA256 in `X-Webhook-Signature` over the JSON body)
- Safe, dependable delivery — sent in the background, never to an internal address, and paused automatically if your endpoint keeps failing

## Event types

For what each `Delivery` and `InboundEmail` status means end-to-end, see [Statuses & Lifecycle](lifecycle.md).

| Event                           | Fires when                                                                                                         |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `inbound_email_received`        | Mail arrived for a registered mailbox (or a domain with catch-all forward/discard)                                 |
| `inbound_email_bounce_received` | Mail arrived at the bounce address, i.e. a DSN                                                                     |
| `inbound_email_forwarded`       | Mail for a forwarding mailbox was sent on to that mailbox's destination address                                    |
| `delivery_delivered`            | The recipient's MX accepted the message                                                                            |
| `delivery_deferred`             | A transient SMTP failure, or sending to its domain is paused; the delivery will be retried. A paused deferral carries `reason: "recipient_domain_paused"` |
| `delivery_failed`               | We could not deliver it at all: the recipient is suppressed, or the retries ran out. `reason` says which: `suppressed` or `exhausted` |
| `delivery_bounced`              | The recipient's MX rejected it, or a DSN came back for it later; the payload's `raw` carries the DSN (first 64 KB). `category` is always present: `invalid`, `full`, `oversized`, `blocked`, or `unknown`, or `null` when the report could not be read. `invalid` is the only value that means the address itself is bad |
| `recipient_domain_paused`       | Sending to the recipient's domain paused because its mail servers refuse this server's IP or tell it to slow down; the payload is the delivery that tripped it, with `recipient_domain` and `provider`. On Outlook.com, Yahoo and Gmail the pause covers every domain they host, and `provider` is `outlook`, `yahoo` or `gmail`; elsewhere it is the domain itself. Mail for that domain waits and retries as `delivery_deferred` until the pause ends, after an hour by default when told to slow down, or until the server's operator resumes it, and fails if the domain is still paused when its retries run out |
| `recipient_domain_resumed`      | Sending to that domain resumed, because the pause ended or the server's operator resumed it; same payload as `recipient_domain_paused` |
| `sending_token_created`         | An admin created a sending token for the domain; the payload is `domain_id`, `domain` and the token's `token_name` |
| `sending_token_revoked`         | An admin revoked a sending token; same payload as `sending_token_created` |
| `sending_token_refused`         | A valid sending token was used from an IP outside the domain's allowed IPs and the request was refused, with `403` over the API or `535` at SMTP AUTH; the payload adds the refused `ip`. Sent at most once an hour for each token and address, and at most 10 an hour for each token |


Each delivery — one message to one recipient — ends in exactly one of `delivery_delivered`, `delivery_failed`, or `delivery_bounced`, after any number of `delivery_deferred`s along the way. The two failures differ by where things went wrong: `delivery_failed` means the message never reached the remote MX, while `delivery_bounced` means the MX received it, turned it down, and told us why. A hard bounce sends `delivery_bounced` and nothing else.

`inbound_email_forwarded` is a second event about the same piece of mail rather than an alternative to the first: mail addressed to a forwarding mailbox fires `inbound_email_received` when it arrives, then this one once it has been re-sent to the mailbox's destination address, ARC-sealed with the relay's own key. Its payload is the same inbound payload, `authentication` object and all, so the two bodies differ only in the envelope's `event`; the destination it went to isn't in the payload, but rides on the event itself, which `GET /mailpieces/:id` returns among the mailpiece's `events`. Mail we won't pass on — a sender not yet approved as a contact or explicitly denied, a `From` that no aligned DKIM, SPF, or DMARC pass vouches for, or a forwarding loop — is held instead and fires no forwarding event.

PostRider records other events too. An inbound email held, failed, discarded, or incinerated; an outbound message incinerated; a webhook deactivated; a domain's DNS verified or lost. Those are for the events feed in the admin UI only, and cannot be subscribed to.

Every webhook subscribed to an event gets the same body for it, with two exceptions PostRider detects from the URL alone: an Action Mailbox relay ingress receives the raw message, and a Slack incoming webhook receives a one-line notification rather than a payload. Both are described below.

Payload shape:

```json
{ "event": "inbound_email_received", "payload": { "id": "…", "rcpt_to": "support@yourdomain.com", "from": "…", "to": "…", "subject": "…", "headers": ["…"], "authentication": { "spf": "pass", "dkim": "pass", "dmarc": "pass", "dmarc_policy": "quarantine", "arc": "none", "iprev": "pass", "remote_host": "mail.theirdomain.com", "authentication_results": "mx.example.com; iprev=pass (mail.theirdomain.com) policy.iprev=203.0.113.7; spf=pass smtp.mailfrom=sender@theirdomain.com; dkim=pass header.d=theirdomain.com; dmarc=pass header.from=theirdomain.com", "from_aligned": true }, "html": "…", "text": "…", "attachments": [{ "type": "attachment", "filename": "…", "contentType": "image/jpeg", "size": 1234, "checksum": "…", "contentId": "<ii_abc>", "cid": "ii_abc", "related": true, "url": "https://…/rails/active_storage/blobs/redirect/…/photo.jpg?disposition=attachment" }] } }
```

The payload gives you the parsed message — headers, bodies, and attachment metadata (filename, type, size, checksum, cid, …) — but not the raw RFC822 bytes. Shipping those would mean parsing, JSON-encoding, and signing a large message all over again for every webhook you've subscribed.

So each attachment comes with a `url` instead: a link that downloads just that one file's bytes (with `Content-Disposition: attachment`). It is an authenticated endpoint like the rest of the API — fetch it with `Authorization: Bearer $ACCESS_TOKEN` (a `read` token is enough), issued to an identity with a user on this account who has access to the domain. The link stays good only until the inbound email is incinerated after `RETENTION_DAYS`, so grab what you need promptly.

**Treat the payload as sensitive.**

Inline images set `related: true` and a `cid` you can match to the `cid:` references in `html`. Want the whole message instead? Use an Action Mailbox relay webhook (below), which POSTs it as `message/rfc822`, or fetch the mailpiece's `raw_url` from `GET /mailpieces/:id` (also a bearer-token download).

One webhook serves every mailbox on its domain, so `rcpt_to` is the envelope recipient that tells them apart — the `To` header won't, since a Bcc'd or plus-addressed message never names it. `id` is the mailpiece id: pass it to `GET /mailpieces/:id` for anything the payload leaves out.

The `authentication` object carries the SPF, DKIM, DMARC, and ARC verdicts and is omitted only when none was recorded. `dmarc` says whether the check failed; `dmarc_policy` says what the sender's domain asked receivers to do about a failure — `none`, `quarantine`, or `reject` — and is absent when the domain publishes no DMARC record. A `fail` under `p=reject` is a message the domain owner disowns; a `fail` under `p=none` is routine for mailing lists. `arc` reports the chain itself — `pass` means intact, `fail` broken, `none` absent, with `arc_sealer` naming who sealed it when there is a chain. An intact chain tells you who sealed it, not whether to believe them: anyone can seal a chain over a message of their own, so do not treat `arc=pass` as overriding `dmarc`.

`iprev` is about the connecting host rather than the message: `pass` when the address's reverse name resolves back to it, `fail` when the name points elsewhere, `permerror` when the address has no name at all, which is usual for residential and botnet addresses and rare for a real mail server. `remote_host` is that name, present only on a `pass`: any operator can write any name in their own reverse zone, so a name that did not resolve back is not reported.

`from_aligned` is the short answer to "does the `From` address actually belong to whoever authenticated" — true when an aligned DKIM signature or SPF pass vouches for the `From` domain, even where that domain publishes no DMARC record. It is always present once anything was recorded, so `false` means not aligned rather than not checked.

`authentication_results` is the full RFC 8601 string, identical to the `Authentication-Results` header an Action Mailbox relay receives (below) and to the `authentication_results` field on `GET /mailpieces/:id`. It is the same verdict as the fields beside it, but it keeps the identifiers those drop — `header.d=`, `smtp.mailfrom=`, `header.from=`. Reach for it when a bare `pass` isn't enough: `dkim=pass` on a `header.d=` you don't recognise vouches for that signer, not for the `From` domain.

## Delivery log

Every dispatch attempt is recorded. Admins can review a webhook's attempts at:

```
GET /domains/:domain_id/webhooks/:webhook_id/deliveries
```

Admin-only, JSON only, newest first:

```json
[
  {
    "id": "…",
    "state": "completed",
    "created_at": "2026-07-15T18:00:00Z",
    "updated_at": "2026-07-15T18:00:07Z",
    "request": { "headers": { "User-Agent": "postrider/1.0.0 Webhook", "X-Webhook-Timestamp": "…" } },
    "response": { "code": 200 },
    "event": { "id": "…", "action": "inbound_email_received", "created_at": "2026-07-15T18:00:00Z" }
  }
]
```

`state` is one of `pending`, `in_progress`, `completed`, or `errored`. `request` and `response` are `null` until the attempt runs; the outgoing `X-Webhook-Signature` (and any `Authorization`) header is stripped from the logged `request`. `response` carries the endpoint's HTTP `code`, or an `error` string when no response came back (e.g. `connection_timeout`, `dns_lookup_failed`, `response_too_large`).

## Action Mailbox relay integration

Name a webhook's URL the way Rails expects — ending in `/rails/action_mailbox/relay/inbound_emails` — and PostRider notices, then switches that webhook to Rails' built-in [Action Mailbox relay](https://guides.rubyonrails.org/action_mailbox_basics.html) format. Your Rails app takes the mail as-is, with no adapter code to write.

To enable it, create a webhook subscribed to `inbound_email_received` and/or `inbound_email_bounce_received` whose URL is:

```
https://your-app.example.com/rails/action_mailbox/relay/inbound_emails
```

No separate setting is needed — the URL shape alone triggers it. Only `inbound_email_received` and `inbound_email_bounce_received` may be subscribed on a webhook whose URL matches this pattern; PostRider's model validation rejects other event types on it. Delivery events for mail you send have no raw message to relay, so subscribe them on an ordinary JSON webhook instead.

A relay receives the bytes and nothing else, so what we know beside the message rides along as trace headers prepended to it:

| Header | Value |
| ------ | ----- |
| `Delivered-To` | The envelope recipient — which of the domain's mailboxes this arrived at |
| `Authentication-Results` | What we concluded about SPF, DKIM, DMARC and ARC, stamped under our authserv-id |
| `X-PostRider-Mailpiece-Id` | The mailpiece id, for `GET /mailpieces/:id` |

`Authentication-Results` is the same verdict the JSON payload reports in its `authentication` object, and the same string an ARC seal commits to when the message is forwarded. You can trust it as the only one in the message: whatever the sender claimed in an `Authentication-Results` header of its own is stripped at the MX before we authenticate, so there is never a second instance to tell apart from ours. **Treat an absent header as unauthenticated, never as a pass** — we omit it rather than guess when authentication couldn't be run.

Forwarded mail is the one place that can't omit: an ARC set must carry an `ARC-Authentication-Results`, so when we reached no verdict the seal states `none` — RFC 8601 for "no checks were run", not a pass. Absent here and `none` there mean the same thing.

They're prepended, never substituted, so a sender's DKIM signature still verifies: DKIM signs header fields from the bottom up, and a fresh instance at the top falls outside it. The bytes you receive therefore differ from the stored original by exactly these lines — fetch `raw_url` from `GET /mailpieces/:id` (with your access token) if you need the message as it arrived.

A relay is the one path that hands you bytes without a fetch: PostRider POSTs them to you, authenticating itself with the ingress password below. Nothing about it changed.

On the receiving Rails app, set:

- `config.action_mailbox.ingress = :relay` in `config/environments/production.rb`
- `RAILS_INBOUND_EMAIL_PASSWORD` (or `action_mailbox.ingress_password` in Rails credentials) to the webhook's **signing secret**, shown on the webhook's show page in the admin UI

For such a webhook, PostRider sends the raw RFC822 bytes of the original inbound email as the entire POST body, with `Content-Type: message/rfc822` and `Authorization: Basic base64("actionmailbox:<signing secret>")` — instead of the normal JSON payload and `X-Webhook-Signature` header. If you see a `401` or `415` from the receiving app, check the password and `Content-Type` handling first.

## Slack integration

Slack's [incoming webhooks](https://api.slack.com/messaging/webhooks) speak their own shape — `{"text": "…"}` and nothing else — so a webhook pointed at one and sent the normal JSON payload earns a `400` on every event, and ten consecutive failures spanning an hour deactivate it.

As with the relay above, the URL shape alone is the setting. Create a webhook whose URL is the one Slack gave you:

```
https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX
```

and PostRider posts a Slack message instead:

```json
{"text":"Received inbound mail for support@example.com <https://postrider.example.com/1/mailpieces/03gk…|Open in PostRider>"}
```

The sentence is the same one the admin UI shows in a domain's event feed, HTML-escaped because Slack reads `&`, `<`, and `>` as markup, followed by a link to the mailpiece — or to the domain or webhook, for events about those. Any event type may be subscribed.

That sentence and that link are the whole body. A Slack webhook is a notification, not a data feed: none of the JSON payload above travels with it — not the `authentication` verdicts, not `rcpt_to`, not the attachment links, not the delivery's SMTP result. Subscribing `inbound_email_received` on a Slack URL gets you "Received inbound mail for support@example.com", and you follow the link for the rest. When you need the data, point a webhook at your own endpoint; subscribe both if you want the nudge as well.

The link needs `BASE_URL` set and the mailpiece still on disk; without either, building it raises and the delivery errors like any other failure.

The signature headers ride along unchanged and Slack ignores them; the credential here is the URL itself, which anyone holding can post to the channel with. Treat it the way you'd treat a password.

Slack answers `200` with a body of `ok`, so the delivery records as completed. Only Slack's incoming-webhook URLs are recognized — a Workflow Builder trigger URL takes arbitrary JSON and gets PostRider's ordinary payload.

**Account Settings** configures the **bounce address** (inbound DSN mail routed to `inbound_email_bounce_received`); the relay hostname DNS check lives under Server Settings. Mailboxes, sending tokens, and webhooks are sub-resources of a domain, managed from that domain's page in the admin UI.