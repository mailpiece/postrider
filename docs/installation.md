# Installation

Your app is up — now let's make it send. [Deployment & operations](deployment.md) gets a container running; this guide takes over from there, from first sign-in to a verified domain sending real mail.

## 1. Create the first account

Open the app's public URL. While no account exists it takes you to signup: type your email, create a passkey with your device's fingerprint, face or PIN, add your name, and you're in. No email is sent, so this works before any mailer is set up.

Creating that first account closes signup for good. A self-hosted install is single-account: `/signup` now redirects to sign-in, and everyone else gets in by invitation, creating their own passkey as they join.

To use another device, such as a phone: a passkey saved in iCloud Keychain, Google Password Manager or 1Password is already there. Otherwise open your profile where you're already signed in and use the single-use sign-in link under **Devices**. It works once, within 4 hours, and signs that device in. To have a passkey on that device too, save one in a synced password manager from a device that has a passkey.

Lost every device? If nobody can sign in, open a Rails console: `bin/kamal console` on a Kamal deploy (`-d <name>` for an overlay), `once exec <host> bin/rails console` under [ONCE](deployment.md#deploying-with-once), or `docker exec -it postrider bin/rails console` on plain Docker:

```ruby
identity = Identity.find_by(email_address: "you@example.com")
identity.passkeys.destroy_all
puts Rails.application.routes.url_helpers.session_transfer_url(identity.transfer_id)
```

This clears the person's passkeys, then prints a sign-in link. Opening it signs you in, and with no passkeys left you add your first passkey without being asked to confirm with one.

A teammate who lost a passkey that was not synced: run the first two lines for their email to clear their passkeys, then an admin shows them their sign-in link from their page under **People**, and they add a passkey.

That first account arrives complete: an owner (you), a system user, an invite code, and a settings row. You're also marked **staff** — the relay's operator — which is what gets you into Server Settings at `/adminland`. Nobody who signs up or is invited later gets that; it's granted once, here. From here on, every URL is prefixed with the account slug (`/1/...`).

## 2. Publish the relay's own DNS

**Server Settings** (`/adminland/settings`, staff only) has a **DNS records** screen that checks A/AAAA, PTR, SPF and the certificate delegation against live DNS — weekly, on Sunday at 3:30am, or on demand with **Check DNS now**. Publish these once on `<RELAY_HOSTNAME>` (and its IP), and they cover every domain you'll ever add:


| Record     | Value                                                    | Notes                                                                                                                                                                    |
| ---------- | -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **A/AAAA** | `<RELAY_HOSTNAME>` → this server's IP                    | Everything else depends on this resolving                                                                                                                                |
| **MX**     | `<RELAY_MAIL_DOMAIN>. MX 10 <RELAY_HOSTNAME>.`           | Self-pointing when the two names are equal, which is fine — this name is an A host, not a CNAME. Lets VERP bounces (`bounces+…@<RELAY_MAIL_DOMAIN>`) be delivered back here. Not per customer domain |
| **PTR**    | this server's IP → `<RELAY_HOSTNAME>`                    | Reverse DNS. Only your hosting provider can set it; many receivers require it                                                                                            |
| **SPF**    | `<RELAY_MAIL_DOMAIN>. TXT "v=spf1 a:<RELAY_MAIL_DOMAIN> -all"` | One relay-wide record. Authorizes the [custom Return-Path](#4-advanced-verification-optional) for every domain at once                                                   |
| **NS**     | `_acme-challenge.<RELAY_HOSTNAME>. NS <RELAY_HOSTNAME>.` | Delegates the Let's Encrypt challenge to the relay, which answers it itself on port 53. One more for `SUBMISSION_HOSTNAME` when it differs; the **TLS certificate** screen lists them. See [TLS certificate](deployment.md#tls-certificate) |


`RELAY_MAIL_DOMAIN` is the relay's outbound identity and defaults to `RELAY_HOSTNAME`, so every row above lands on one name unless you set it. Giving sending its own name lets it move to its own address later without customers republishing anything — see [Sending identity](deployment.md#sending-identity). When you do, it needs its own A/AAAA record and PTR alongside the rows above.

In the SPF record, use the `a:<RELAY_MAIL_DOMAIN>` mechanism, not `mx` — that name is authorized by its own A record. The MX row does a different job entirely: it tells receivers where to *deliver* mail for that hostname (the bounce Return-Path), not how SPF authorizes sending.

By the way: the home page is **Mailpieces**, the mail log — counts of held, failed, withheld, deferred, queued and discarded mail, then the delivered mail itself. It's not the DNS checker.

## 3. Add a domain

Head to **Domains → Add domain.** Use an inbound subdomain (say, `inbound.example.com`) so apex mail on `example.com` stays put on Google, M365, or wherever it lives today. PostRider generates a DKIM keypair for you, and the domain's page spells out exactly what to publish — checked on demand with **Check DNS now**, and re-checked daily at 3am once the domain is verified:


| Record                | Value                                                    | Notes                                                                                     |
| --------------------- | -------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| **MX** (preferred)    | `<domain>. MX 10 <RELAY_HOSTNAME>.`                      | Inbound. Prefer a subdomain so apex mail stays elsewhere                                  |
| **CNAME** (alternate) | `<domain>. CNAME <RELAY_HOSTNAME>.`                      | Same target. Publish MX *or* CNAME, not both; on Cloudflare set **DNS-only** (grey cloud) |
| **DKIM**              | `postrider._domainkey.<domain>. TXT "v=DKIM1; k=rsa; …"` | Required to *send* as this domain                                                         |


**Sending hinges on DKIM alone.** A sending token can't send from the domain until `dkim_status` is `ok`, so for outbound, nail this record first. Inbound just needs the MX or CNAME pointing at the relay.

Two mailboxes — `postmaster` and `dmarc-reports` — are created automatically. Catch-all stays **disabled** by default, so unregistered recipients are rejected; turn on discard or forward only if you actually want `*@<domain>`.

## 4. Advanced verification (optional)

By default, each outbound delivery uses a relay-owned VERP Return-Path (`bounces+<id>.<hmac>@<RELAY_MAIL_DOMAIN>`, defaulting to `<RELAY_HOSTNAME>` — see the relay [MX in step 2](#2-publish-the-relays-own-dns)). Your mail still authenticates on its DKIM signature. Publish these two records to move the Return-Path onto your own domain, and you gain an aligned SPF pass alongside DKIM:


| Record          | Value                                                                         |
| --------------- | ----------------------------------------------------------------------------- |
| **DMARC**       | `_dmarc.<domain>. TXT "v=DMARC1; p=none; rua=mailto:dmarc-reports@<domain>;"` |
| **Return-Path** | `mailer.<domain>. CNAME <RELAY_MAIL_DOMAIN>.`                                 |


Both records must verify — plus DKIM — before the custom Return-Path switches on. The `rua` reports come back to your app as `inbound_email_received` webhooks.

> [!WARNING]
> On Cloudflare, the CNAME must be **DNS-only (grey cloud)**, not proxied — a proxied record won't verify, and the custom Return-Path never switches on.

This is exactly what the relay-wide SPF record from [step 2](#2-publish-the-relays-own-dns) is for — without it, mail under the custom Return-Path shows `spf=none`.

Start at `p=none`, then tighten once you've confirmed alignment.

## 5. Create a sending token and send a test

Go to **Sending tokens → New.** The token is shown **once**, at creation — copy it now. Each token is pinned to one domain and can only send `from` an address in it. There's no ENV fallback: tokens created here are the only way to authenticate outbound mail.

```bash
curl https://<your-app>/1/messages \
  -H "Authorization: Bearer $SENDING_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ "from": "hello@<domain>", "to": ["you@example.com"], "subject": "Hello", "text": "It works." }'
```

The same token doubles as the password for SMTP submission (port 587, STARTTLS, username `postrider`). See [the API docs](api.md) for the full surface.

Now watch it land: the message shows up under **Mailpieces** (`/1/mailpieces/queued`, and `/1/mailpieces` once delivered), and delivery reports back as a `delivery_delivered` / `delivery_failed` / `delivery_bounced` webhook.

## 6. Receiving mail (optional)

Point the domain at the relay with an **MX** (preferred) or **CNAME**, then register your mailboxes. Unregistered recipients are rejected at SMTP time unless the domain's catch-all policy is set to discard or forward (disabled by default).

- **Mailboxes**: register the addresses you want to accept (`local_part` on a domain). Plus-addressing (`support+tag@…`) matches the base mailbox.
- **Forwarding**: a mailbox can forward screened-in mail to another address once that address confirms. The confirmation link goes out from `noreply@<domain>`, so verify the domain's DKIM first, then send it from the mailbox's page.
- **Webhooks**: one or more HTTPS endpoints, each with a signing secret and subscribed events. A URL ending in `/rails/action_mailbox/relay/inbound_emails` is auto-detected and delivered in Rails' Action Mailbox wire format, so no adapter code is needed. See [Webhooks](webhooks.md).
- **Bounce routing**: **Account Settings → Bounce routing** sets the address DSNs route to; it must live on a registered domain.
- **Personal access tokens**: for pulling mail via `GET /mailpieces` (shown once at creation). See [the API docs](api.md#personal-access-token-permissions).
