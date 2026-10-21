# Statuses & Lifecycle

This page is the canonical reference for what each status means on a `Message`, `Delivery`, or `InboundEmail`. Other docs link here instead of re-explaining a status inline.

## Delivery status

One `Delivery` exists per recipient of an outbound `Message`. `Message` itself has no status of its own — its lifecycle is tracked per recipient, on its `deliveries`.

| Status       | Meaning                                                                          |
| ------------ | --------------------------------------------------------------------------------- |
| `queued`     | Waiting to be attempted — the initial state, and again between retries after a deferral |
| `delivered`  | The recipient's MX accepted the message                                         |
| `deferred`   | A transient SMTP failure occurred, or sending to its domain is paused; the delivery will be retried |
| `bounced`    | The recipient's MX rejected it outright, or a DSN reported the failure later    |
| `exhausted`  | Every retry (over ~2 days) was used up without a successful delivery            |
| `suppressed` | The recipient was on this domain's suppression list, so delivery was skipped entirely |
| `withheld`   | The message contained one of the domain's blocked phrases, so it was never sent    |

`queued` and `deferred` are the only in-flight states; every other status is final. `exhausted` and `suppressed` both surface as a `delivery_failed` webhook (see below). `withheld` reaches no webhook at all.

## InboundEmail status

Tracks one piece of inbound mail from receipt through forwarding.

| Status       | Meaning                                                                          |
| ------------ | --------------------------------------------------------------------------------- |
| `pending`    | Received, not yet processed                                                     |
| `processing` | Authentication and forwarding are in progress                                   |
| `delivered`  | Forwarded to your webhook successfully (or, for a bounce DSN, correlated back to the originating delivery) |
| `failed`     | Processing could not complete (e.g. it stayed stuck for over a day)             |
| `bounced`    | Discarded rather than forwarded — no registered mailbox claimed it, or a DSN couldn't be correlated to a delivery |
| `held`       | Addressed to a forwarding mailbox but not passed on — no aligned DKIM, SPF, or DMARC pass vouches for its `From` (such mail is filed under no contact), the sender isn't an approved contact (a sender first seen starts out denied), or the message was going round a forwarding loop |

`held` is the one inbound status that isn't final: the mail is kept as it arrived, and approving the sender releases everything held from them — each message that nothing else blocks is forwarded then and becomes `delivered`. Held mail nobody releases ages out on its own clock (`HELD_RETENTION_DAYS`, default 90 days) rather than the ordinary retention period.

Despite the name, an `InboundEmail`'s `bounced` status is about the inbound message being discarded, not about an outbound delivery bouncing — see `Delivery`'s `bounced` above for that.

## Delivery status to webhook event

Delivery statuses and Action, the two ends of the same fact, don't always share a name. This table repeats the mapping from [Webhooks](webhooks.md#event-types) for a status-first lookup:

| Delivery status         | Webhook event         |
| ------------------------ | ---------------------- |
| `delivered`              | `delivery_delivered`  |
| `deferred`               | `delivery_deferred`   |
| `exhausted`, `suppressed` | `delivery_failed`     |
| `bounced`                | `delivery_bounced`    |

`queued` fires no webhook — it's the waiting state before an attempt.

Inbound mail follows the same idea: a `delivered` `InboundEmail` fires `inbound_email_received` (or `inbound_email_bounce_received` for a DSN landing at the bounce address), and one that reached `delivered` by being forwarded fires `inbound_email_forwarded` as well. `failed`, `held`, and a discarded `bounced` are recorded as events but are feed-only in the admin UI — they cannot be subscribed to by a webhook.
