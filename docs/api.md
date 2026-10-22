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
- `write` — everything `read` allows, plus `DELETE /mailpieces/:id`, creating domains, checking their DNS and creating sending tokens

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


Each entry carries `id`, `name`, `catch_all_policy`, the `mx_status`, `dkim_status`, `dmarc_status` and `return_path_status` of its last DNS check (`null` until checked), `verified`, `created_at` and `url`.

An account admin's `write` token changes what a domain does with mail for an address with no mailbox: `PATCH /domains/:domain_id/catch_all` with `{ "catch_all_policy": "disabled" }` (or `discard`, `forward`) returns the domain.

## Creating a domain

Requires a `write` token belonging to an account admin. The name is stored lowercased and must be unique across the server:

```
POST /123456789/domains
Authorization: Bearer $ACCESS_TOKEN
Content-Type: application/json

{ "domain": { "name": "lists.example.com" } }
```

Returns `201` with the domain in the index's format: `{ "id", "name", "catch_all_policy", "mx_status", "dkim_status", "dmarc_status", "return_path_status", "verified", "created_at", "url" }`. Every active user in the account gets access to the new domain.

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
| `GET /mailpieces`     | Paged metadata for delivered mail: deliveries that were delivered and inbound mail that was accepted |
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