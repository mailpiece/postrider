# PostRider API

PostRider handles inbound and outbound mail, and reports status changes through [webhooks](webhooks.md).

### **Inbound**

Receives mail addressed to your domains, via registered mailboxes or the domain's catch-all policy.

### **Outbound**

Sends your mail, via the HTTP API or the SMTP submission listener.

## Authentication

Every path below sits under the account's number, the one in the app's URLs once you sign in: `POST /messages` on account `123456789` is `https://postrider.example.com/123456789/messages`.

| Credential                | Created at                         | Used for                                   |
| ------------------------- | ---------------------------------- | ------------------------------------------ |
| **Sending token**         | A domain's **Sending tokens** page | `POST /messages`; SMTP submission password |
| **Personal access token** | **Personal access tokens** page    | `GET /mailpieces`; creating domains and sending tokens |


A sending token is bound to a single verified domain.

## Personal access token permissions

Each personal access token has one permission:

- `read` — all `GET` endpoints (`GET /mailpieces`, `GET /mailpieces/:id`)
- `write` — everything `read` allows, plus `DELETE /mailpieces/:id`, creating domains, checking their DNS, creating sending tokens and managing mailboxes and webhooks

## Creating a sending token

Requires a `write` token belonging to an account admin. The domain need not be verified yet — but the token can't send until it is:

```
POST /123456789/domains/:domain_id/sending_tokens
Authorization: Bearer $ACCESS_TOKEN
Content-Type: application/json

{ "sending_token": { "name": "billing-emails" } }
```

Returns `201` with `{ "id", "name", "domain", "token" }`. The `token` value, which begins with `postrider_`, is shown only in this response.

To manage tokens later: `GET /domains/:domain_id/sending_tokens` lists them, paged like the other lists; `DELETE /domains/:domain_id/sending_tokens/:id` revokes one.

### Example

```bash
curl https://postrider.example.com/123456789/domains/$DOMAIN_ID/sending_tokens \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{ "sending_token": { "name": "billing-emails" } }'
```

### Listing sending tokens

```bash
curl https://postrider.example.com/123456789/domains/$DOMAIN_ID/sending_tokens \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json"
```

### Revoking a sending token

```bash
curl -X DELETE https://postrider.example.com/123456789/domains/$DOMAIN_ID/sending_tokens/$SENDING_TOKEN_ID \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json"
```

### Responses

| Status | Cause                                                                             |
| ------ | ---------------------------------------------------------------------------------- |
| `200`  | Success (listing or showing a token)                                             |
| `201`  | Created; returns `{ "id", "name", "domain", "token" }` (creation only)            |
| `204`  | Revoked, no body (revocation only)                                                |
| `401`  | Missing or invalid personal access token                                         |
| `403`  | Token's user is not an account admin, or the account/user is not active          |
| `404`  | No such domain, or no such sending token, under this token's user                |
| `422`  | `name` is blank (creation only)                                                   |

## Sending via HTTP API

```
POST /123456789/messages
Authorization: Bearer $SENDING_TOKEN
Content-Type: application/json
```

A sending token can only send `from` addresses in its own domain, and only after that domain's DKIM is verified.

### Idempotency

Optionally set an `Idempotency-Key` header (max 255 characters, scoped per sending token):

- Replaying a settled key returns the original `201` without resubmitting.
- A key still in flight returns `409 Conflict` with `Retry-After: 1`.
- Keys expire after 24 hours.



### Request body


| Name                            | Type                                            | Notes                                                                                                                                                                                                                                                                    |
| ------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `from`                          | string                                          | **Required.** Bare address or `"Name <address>"`                                                                                                                                                                                                                         |
| `from_name`                     | string                                          | Display name; overrides one embedded in `from`                                                                                                                                                                                                                           |
| `to`, `cc`, `bcc`               | array or comma-separated string                 | At least one recipient required across the three; 50 max combined. Entries may be `"Name <address>"`. `bcc` recipients are delivered to but never appear in the message                                                                                                  |
| `subject`                       | string                                          | Optional                                                                                                                                                                                                                                                                 |
| `text`, `html`                  | string                                          | At least one required                                                                                                                                                                                                                                                    |
| `reply_to`, `reply_to_name`     | string                                          | Optional                                                                                                                                                                                                                                                                 |
| `in_reply_to`                   | string                                          | `Message-ID` being replied to, e.g. `<parent@example.com>`                                                                                                                                                                                                               |
| `references`                    | string                                          | Space-separated `Message-ID`s, e.g. `<a@x> <b@x>`                                                                                                                                                                                                                        |
| `list_unsubscribe`              | string                                          | Sets the `List-Unsubscribe` header. An `https://` URL also enables RFC 8058 one-click unsubscribe                                                                                                                                                                        |
| `envelope_from` / `return_path` | string                                          | SMTP `MAIL FROM` override (aliases). An **empty** `envelope_from` sends a null return path; an empty `return_path` alone falls back to the default                                                                                                                       |
| `tags`                          | array or string                                 | 10 max. Not embedded in the message; included in `delivery_*` webhook payloads for filtering                                                                                                                                                                             |
| `metadata`                      | object of string key/values                     | 10 entries max, values ≤ 1000 characters. Not embedded in the message; echoed in `delivery_*` webhook payloads for correlating with your records                                                                                                                         |
| `headers`                       | object                                          | 50 max. Cannot override first-class headers (`From`, `To`, `Cc`, `Bcc`, `Subject`, `Reply-To`, `In-Reply-To`, `References`, `Message-ID`, `Date`, `Sender`, `Content-Type`, etc.)                                                                                        |
| `attachments`                   | array of `{ name, content_type, content, cid }` | 20 max; `content` is base64. Allow-listed extensions only: `jpeg jpg png gif txt pdf docx xlsx pptx csv att ics ical html zip auf xml dwg`. Filenames may contain at most one period. Setting `cid` (e.g. `<logo.cid>`) makes it inline, referenced via `cid:` in `html` |


The complete message — headers, body, and attachments — must fit under `OUTBOUND_MAX_MESSAGE_SIZE` (see [Configuration](deployment.md#configuration-env)). For large files, host them elsewhere and link to them instead.

### Responses

Success returns `201 Created` with `{ "id", "status": "queued", "message_id", "recipients", "submitted_at" }`:

- `message_id` — the `Message-ID` stamped on the mail, echoed in webhooks so you can match them.
- `recipients` — every address a delivery was created for, including `cc` and `bcc`.

Delivery happens asynchronously; each step arrives as a `delivery_delivered`, `delivery_deferred`, `delivery_failed`, or `delivery_bounced` webhook.


| Status | Cause                                                                                                                        |
| ------ | ---------------------------------------------------------------------------------------------------------------------------- |
| `400`  | Missing `from`, or overlong `Idempotency-Key`                                                                                |
| `401`  | Missing or invalid sending token                                                                                             |
| `403`  | `from` not authorized for this token, account not active, or the client's IP is not among the domain's allowed IPs           |
| `409`  | Idempotency key still in flight                                                                                              |
| `422`  | Field-level validation errors                                                                                                |
| `429`  | Rate-limited: 10/min per IP without a valid token, or `SUBMISSION_RATE_LIMIT` (default 30/min) per account, shared with SMTP |

When a domain has allowed IPs set, a client reaching the API over IPv6 is refused, since the list holds IPv4 only. Behind a load balancer or proxy, set `TRUSTED_PROXIES` to its ranges (see [Configuration](deployment.md#configuration-env)), or the check sees the balancer's address instead of the client's.




### Example

```bash
curl https://postrider.example.com/123456789/messages \
  -H "Authorization: Bearer $SENDING_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: welcome-42" \
  -d '{
    "from": "Announcements <news@lists.example.com>",
    "to": ["subscriber@example.com"],
    "subject": "Hello",
    "text": "Hello there",
    "tags": ["welcome"]
  }'
```

## Sending via SMTP

Point your SMTP client at the submission listener (see [Ports](deployment.md#ports)) with STARTTLS. Username: `postrider`. Password: your sending token.

When the domain has allowed IPs set, a client outside them, or one connecting over IPv6, is refused at `AUTH` with `535`.

Every message must include both a `From` and a `To` header. Identical messages (same envelope and body) submitted within 24 hours are deduplicated, so retries won't double-deliver.

Two optional headers are read and then stripped before sending:


| Header               | Effect                                                                                                                       |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `X-PostRider-Tags`   | Single tag or comma-separated list. Recorded on the message and included in `delivery_*` webhooks — same as the API's `tags` |
| `X-List-Unsubscribe` | Promoted to a real `List-Unsubscribe` header; an `https://` URI also enables RFC 8058 one-click unsubscribe                  |




## Listing domains

Authenticate with a personal access token (`read` permission is sufficient): `Authorization: Bearer $ACCESS_TOKEN`.


| Endpoint                  | Returns                                                                      |
| ------------------------- | ---------------------------------------------------------------------------- |
| `GET /domains`            | Paged list of the verified domains this token's user can use, those whose DKIM record checked out, by name |
| `GET /domains/unverified` | Domains whose DKIM record is missing, wrong or not yet checked, in the index's format |


Each entry carries `id`, `name`, `catch_all_policy`, the `mx_status`, `dkim_status`, `dmarc_status` and `return_path_status` of its last DNS check (`null` until checked), `verified`, `receiving`, `sending`, `bulk`, `created_at` and `url`.

A domain with `receiving` false refuses inbound mail, and one with `sending` false refuses new messages; both are `true` until an admin turns them off. A domain with `bulk` true has its mail paced per mail provider: by default one message every 30 seconds to Outlook.com and Yahoo, and every 2 seconds to Gmail and to each other recipient domain, at rates the server's operator can change. Forwards from its mailboxes are paced too, while retries go out on their own schedule. It is `false` until an admin turns it on.

An account admin's `write` token changes what a domain does with mail for an address with no mailbox: `PATCH /domains/:domain_id/catch_all` with `{ "catch_all_policy": "disabled" }` (or `discard`, `forward`) returns the domain.

The same token turns a domain's mail on or off, and each returns the domain:

| Endpoint                                 | Does                                                                          |
| ---------------------------------------- | ----------------------------------------------------------------------------- |
| `POST /domains/:domain_id/receiving`     | Turns receiving on                                                            |
| `DELETE /domains/:domain_id/receiving`   | Turns receiving off: inbound mail is refused with a permanent error, bounces of the domain's own mail still come in |
| `POST /domains/:domain_id/sending`       | Turns sending on                                                              |
| `DELETE /domains/:domain_id/sending`     | Turns sending off: new messages are refused, forwards and queued mail still go out |
| `POST /domains/:domain_id/bulk`          | Turns bulk mail on: the domain's new mail is paced per mail provider          |
| `DELETE /domains/:domain_id/bulk`        | Turns bulk mail off: new mail goes out as soon as it is queued                |

## Creating a domain

Requires a `write` token belonging to an account admin. The name is stored lowercased and must be unique across the server:

```
POST /123456789/domains
Authorization: Bearer $ACCESS_TOKEN
Content-Type: application/json

{ "domain": { "name": "lists.example.com" } }
```

Returns `201` with the domain in the index's format: `{ "id", "name", "catch_all_policy", "mx_status", "dkim_status", "dmarc_status", "return_path_status", "verified", "receiving", "sending", "created_at", "url" }`. Every active user in the account gets access to the new domain.

The domain can't send until its DKIM record checks out. The records to publish are on the domain's settings page in the app; once they are in place, [check the domain's DNS](#checking-a-domains-dns).

### Example

```bash
curl https://postrider.example.com/123456789/domains \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{ "domain": { "name": "lists.example.com" } }'
```

### Responses

| Status | Cause                                                                             |
| ------ | ---------------------------------------------------------------------------------- |
| `201`  | Created; returns the domain                                                       |
| `401`  | Missing or invalid personal access token, or a `read` token                       |
| `403`  | Token's user is not an account admin, or the account/user is not active          |
| `422`  | `name` is blank, not a valid domain, or already taken; returns `{ "name": [ ... ] }` |

## Checking a domain's DNS

Requires a `write` token belonging to an account admin:

```bash
curl -X POST https://postrider.example.com/123456789/domains/$DOMAIN_ID/dns_check \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json"
```

Returns `202` with no body. The check runs in the background: poll `GET /domains/:domain_id` until `dkim_status` is `ok` and `verified` is `true`, or watch the domain leave `GET /domains/unverified`.

| Status | Cause                                                                             |
| ------ | ---------------------------------------------------------------------------------- |
| `202`  | Check queued, no body                                                             |
| `401`  | Missing or invalid personal access token, or a `read` token                       |
| `403`  | Token's user is not an account admin, or the account/user is not active          |
| `404`  | No such domain under this token's user                                            |

## Reading a domain's DNS records

Authenticate with a personal access token belonging to an account admin (`read` permission is sufficient):

```bash
curl https://postrider.example.com/123456789/domains/$DOMAIN_ID/dns_records \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json"
```

Returns the records to publish, in publishing order, with what the last check found:

```json
{
  "name": "lists.example.com",
  "verified": true,
  "checked_at": "2026-11-01T10:00:00.000Z",
  "records": [
    { "title": "Inbound", "type": "MX", "name": "lists.example.com", "value": "10 relay.example.", "status": "ok", "error": null },
    { "title": "DKIM", "type": "TXT", "name": "postrider._domainkey.lists.example.com", "value": "v=DKIM1; ...", "status": "ok", "error": null },
    { "title": "DMARC", "type": "TXT", "name": "_dmarc.lists.example.com", "value": "v=DMARC1; p=none; ...", "status": "ok", "error": null },
    { "title": "Return-Path", "type": "CNAME", "name": "mailer.lists.example.com", "value": "relay.example.", "status": "missing", "error": "No CNAME record exists at mailer.lists.example.com" }
  ]
}
```

`name` and `value` are what to publish. `status` is `ok`, `missing` or `invalid`, and `null` until the domain's DNS has been checked, as `checked_at` is; `error` says what was wrong when it is not `ok`. The statuses are a snapshot: to refresh them, [check the domain's DNS](#checking-a-domains-dns) and read the records again.

### Responses

| Status | Cause                                                                             |
| ------ | ---------------------------------------------------------------------------------- |
| `200`  | Success                                                                           |
| `401`  | Missing or invalid personal access token                                          |
| `403`  | Token's user is not an account admin, or the account/user is not active          |
| `404`  | No such domain under this token's user                                            |

## Managing mailboxes

A mailbox is an address the domain receives mail at; mail to `replies+anything@lists.example.com` is accepted for the mailbox `replies` too, but only mail to `replies@lists.example.com` itself is forwarded to its `forward_to`. Requires a `write` token belonging to an account admin (`read` suffices for the `GET`s):

| Endpoint                                   | Does                                                                          |
| ------------------------------------------ | ----------------------------------------------------------------------------- |
| `GET /domains/:domain_id/mailboxes`        | Paged list, by local part; each entry carries `id`, `local_part` and `domain` |
| `GET /domains/:domain_id/mailboxes/:id`    | One mailbox: `{ "id", "local_part", "domain", "forward_to", "forwarding" }`   |
| `POST /domains/:domain_id/mailboxes`       | Adds one; returns `201` with the mailbox                                      |
| `PATCH /domains/:domain_id/mailboxes/:id`  | Changes `forward_to` only; returns the mailbox                                |
| `DELETE /domains/:domain_id/mailboxes/:id` | Removes it; returns `204`                                                     |

```
POST /123456789/domains/:domain_id/mailboxes
Authorization: Bearer $ACCESS_TOKEN
Content-Type: application/json

{ "mailbox": { "local_part": "replies", "forward_to": null } }
```

Setting `forward_to` mails that address a confirmation, and `forwarding` stays `false` until it is confirmed. Each domain comes with `postmaster` and `dmarc-reports`, which can't be removed.

### Example

```bash
curl https://postrider.example.com/123456789/domains/$DOMAIN_ID/mailboxes \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{ "mailbox": { "local_part": "replies" } }'
```

### Responses

| Status | Cause                                                                             |
| ------ | ---------------------------------------------------------------------------------- |
| `200`  | Success (listing, showing or updating a mailbox)                                  |
| `201`  | Created; returns `{ "id", "local_part", "domain", "forward_to", "forwarding" }`   |
| `204`  | Removed, no body                                                                  |
| `401`  | Missing or invalid personal access token, or a `read` token on a write            |
| `403`  | Token's user is not an account admin, or the account/user is not active          |
| `404`  | No such domain, or no such mailbox, under this token's user                      |
| `422`  | Not a valid mailbox, or a reserved one on removal; returns `{ "field": [ ... ] }` |
| `429`  | Too many creates and updates                                                      |

A `422` means `local_part` is blank, not a valid mailbox or already taken, `forward_to` is not an address or is this mailbox, or the mailbox is `postmaster` or `dmarc-reports` (removal only). A `429` means more than 10 creates and updates in 3 minutes, or more than 5 in an hour that set `forward_to`.

## Managing webhooks

A webhook tells your app about a domain's mail; [webhooks.md](webhooks.md) has the event types and payloads. Requires a `write` token belonging to an account admin (`read` suffices for the `GET`s). The app asks for a passkey before a webhook is created or edited; a bearer-token request has no session to confirm with, so it goes straight through:

| Endpoint                                               | Does                                                                          |
| ------------------------------------------------------ | ----------------------------------------------------------------------------- |
| `GET /domains/:domain_id/webhooks`                     | Paged list, by name                                                           |
| `GET /domains/:domain_id/webhooks/:id`                 | One webhook                                                                   |
| `POST /domains/:domain_id/webhooks`                    | Adds one; returns `201` with the webhook                                      |
| `PATCH /domains/:domain_id/webhooks/:id`               | Changes `name`, `signing_secret`, `subscribed_actions`; returns the webhook   |
| `DELETE /domains/:domain_id/webhooks/:id`              | Deletes it and its deliveries; returns `204`                                  |
| `POST /domains/:domain_id/webhooks/:id/activation`     | Turns it on; returns `201` with the webhook                                   |
| `DELETE /domains/:domain_id/webhooks/:id/activation`   | Turns it off; returns `204`                                                   |
| `GET /domains/:domain_id/webhooks/:id/deliveries`      | Paged list of its deliveries, newest first                                    |

Each delivery carries `id`, `state`, `request`, `response`, the `event` it carried (`id`, `action`, `created_at`), `created_at` and `updated_at`.

```
POST /123456789/domains/:domain_id/webhooks
Authorization: Bearer $ACCESS_TOKEN
Content-Type: application/json

{ "webhook": { "name": "Replies", "url": "https://app.example.com/rails/action_mailbox/relay/inbound_emails", "subscribed_actions": ["inbound_email_received", "inbound_email_bounce_received"] } }
```

A webhook is `{ "id", "name", "active", "signing_secret", "subscribed_actions", "payload_url", "created_at", "url" }`: `payload_url` is where it posts, `url` is its own address in the API. `signing_secret` is generated when the webhook is added, unless you give one of at least 16 characters; a `PATCH` with a new one replaces it, as when [rotating a relay's password](webhooks.md#action-mailbox-relay-integration), and a blank one keeps the current secret. The `url` is fixed: to change it, delete the webhook and add another.

`subscribed_actions` is any of `inbound_email_received`, `inbound_email_bounce_received`, `inbound_email_forwarded`, `delivery_delivered`, `delivery_deferred`, `delivery_failed`, `delivery_bounced`, `recipient_domain_paused`, `recipient_domain_resumed`, `sending_token_created`, `sending_token_revoked` and `sending_token_refused`; anything else is dropped. A webhook whose URL ends in `/rails/action_mailbox/relay/inbound_emails` is an [Action Mailbox relay](webhooks.md#action-mailbox-relay-integration) and may only subscribe to `inbound_email_received` and `inbound_email_bounce_received`.

### Example

```bash
curl https://postrider.example.com/123456789/domains/$DOMAIN_ID/webhooks \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{ "webhook": { "name": "Replies", "url": "https://app.example.com/rails/action_mailbox/relay/inbound_emails", "subscribed_actions": ["inbound_email_received"] } }'
```

### Responses

| Status | Cause                                                                             |
| ------ | ---------------------------------------------------------------------------------- |
| `200`  | Success (listing, showing or updating a webhook, or listing its deliveries)       |
| `201`  | Created or activated; returns the webhook                                         |
| `204`  | Deleted or deactivated, no body                                                   |
| `401`  | Missing or invalid personal access token, or a `read` token on a write            |
| `403`  | Token's user is not an account admin, or the account/user is not active          |
| `404`  | No such domain, or no such webhook, under this token's user                      |
| `422`  | Not a valid webhook; returns `{ "field": [ ... ] }`                               |

A `422` means `name` is blank, `url` is not an `https://` URL, `signing_secret` is shorter than 16 characters, or a relay webhook subscribes to actions other than the two it may.

## Listing contacts

Authenticate with a personal access token (`read` permission is sufficient): `Authorization: Bearer $ACCESS_TOKEN`.


| Endpoint                 | Returns                                                                          |
| ------------------------ | -------------------------------------------------------------------------------- |
| `GET /contacts`          | Paged list of the approved senders, those whose mail is forwarded, on domains this token's user can use, newest first |
| `GET /contacts/denied`   | Senders whose mail is held, in the index's format                                |


Each entry carries `id`, `number`, `email`, `name`, `decision` (`approved` or `denied`) and `created_at`.

## Reading mail

Authenticate with a personal access token (`read` permission is sufficient): `Authorization: Bearer $ACCESS_TOKEN`.


| Endpoint              | Returns                                                                                |
| --------------------- | -------------------------------------------------------------------------------------- |
| `GET /mailpieces`     | Paged metadata for all mail, newest first, in either direction and whatever its status |
| `GET /mailpieces/held` | Inbound mail held for a decision on its sender, in the index's format                 |
| `GET /mailpieces/deferred` | Deliveries waiting on a retry, in the index's format                              |
| `GET /mailpieces/queued` | Deliveries not yet attempted and inbound mail not yet processed, in the index's format |
| `GET /mailpieces/failed` | Deliveries that bounced, ran out of retries or were suppressed, and inbound mail that failed, in the index's format |
| `GET /mailpieces/withheld` | Deliveries withheld for a blocked phrase, in the index's format |
| `GET /mailpieces/discarded` | Inbound mail that was discarded: sent to an address nobody registered, or a bounce matching no delivery, in the index's format |
| `GET /mailpieces/:id` | One piece: envelope, status, parsed content (while retained), `raw_url`, `attachments` |


**Index** entries are metadata only (no bodies), so paging is fast. Each includes the SMTP envelope (`mail_from`, `rcpt_to`) and `status`; inbound pieces also carry `spf` / `dkim` / `dmarc` / `arc` verdicts and the sender domain's `dmarc_policy`. Fields are flat here, unlike the nested webhook payload — and note the webhook has no `mail_from`, only the parsed `From` header.

**Single pieces** return the same parsed content as the inbound webhook payload — literally the same source, so one parser handles bodies, headers, and attachments for both push and pull. Authentication is the exception: the webhook nests those fields under an `authentication` object and omits the object entirely when nothing was recorded, while here they sit flat alongside the envelope and appear as `null` when unknown. The one exception is `from_aligned`, which is always a real boolean — `false` means not aligned, never not checked. The names match either way.

Single pieces also carry what the index leaves out to keep list responses small — `arc_sealer`, `iprev` and `remote_host`, `from_aligned`, and the full `authentication_results` string. See [the webhook payload](webhooks.md) for what each means.

**Attachments** match the webhook format: `filename`, `contentType`, `size`, `checksum`, `cid` / `contentId`, `related` (for inline images), plus a `url` that downloads that file's bytes (`Content-Disposition: attachment`). The download URL requires the same `Bearer` auth, and the token's user must have access to the domain.

**Retention:** after `RETENTION_DAYS`, raw content and attachments are deleted; only the metadata row remains. Until then, fetch the complete original via `raw_url` with the same auth.

### Example

```bash
curl "https://postrider.example.com/123456789/mailpieces" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json"
```

```bash
curl https://postrider.example.com/123456789/mailpieces/$MAILPIECE_ID \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json"
```

### Responses

| Status | Cause                                                                 |
| ------ | ---------------------------------------------------------------------- |
| `200`  | Success                                                               |
| `401`  | Missing or invalid personal access token                             |
| `403`  | Account or user is not active                                        |
| `404`  | No such mailpiece, or its domain is not accessible to this token's user (single piece only) |