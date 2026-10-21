# PostRider

PostRider is a self-hosted mail relay: it delivers outbound mail from an HTTP
API and SMTP submission direct to MX with DKIM, receives inbound mail on MX for
the domains an account registers, and reports what happened through webhooks.

These instructions are defaults with reasons, not law — when the code in
front of you disagrees, take the better path and flag the conflict; invariants
(data loss, security, a token or key leaking, mail sent for a domain that did
not authorize it) are surfaced, not overridden. Attack your own diff before
calling it done.

## Deploy

Default branch: `main`

Self-hosted deploys run Kamal against `config/deploy.yml` — see
`docs/deployment.md`. Production runs web, `jobs` (`bin/jobs`) and `smtp`
(`bin/relay`) as separate roles; in development `plugin :postrider` runs the
SMTP listeners inside Puma.

## SMTP

`MxListener` and `SubmissionListener` subclass `MailSmtp::Server` and hold the
mail policy; `Relay::Supervisor` boots them. Listener tests boot the servers
in-process on free ports and drive them with `Net::SMTP`. The TLS certificate
is issued over ACME through `AcmeDnsListener` and stored in
`Relay::Certificate`; the supervisor swaps it into the running listeners, so no
certificate work restarts the app.

## Multi-tenancy is URL-based

Accounts get a decimal `external_account_id` URL prefix. `AccountSlug::Extractor`
sets `Current.account` and moves the slug from `PATH_INFO` to `SCRIPT_NAME`,
so route helpers and request specs that assume a bare root will mislead you.
A global `Identity` (email-based) can hold `Users` in several accounts.

Everything hangs off a `Domain`, and a user sees one only through an `Access`:
screens read through `Current.user.accessible_*`. Configuration is
`ensure_admin`; what describes the server rather than a tenant lives under
`/adminland`, behind `Identity#staff?`.

## UUID primary keys

All tables use UUIDv7 keys, base36-encoded to 25 characters. Fixture UUIDs sort
older than any runtime record. `insert_all` and `upsert_all` need an explicit
`id:`.

## Tokens and keys

`POST /messages` and SMTP submission authenticate with a `SendingToken`, which
sends only for its own verified domain; only its digest is stored. Webhook
signing secrets, DKIM keys, the certificate and the sealing key are encrypted
columns. A forward is ARC-sealed with the relay's key, never signed with the
tenant's DKIM key. Webhook URLs are resolved through Surfguard before they are
called.

Sign-in is by passkey only: no passwords, no email codes, and PostRider sends
no sign-in mail. A new device or a lost one gets a transfer link, which an admin
can also show a teammate; when nobody can sign in, the link is printed from the
Rails console.

## Mail

A `Message` has no status; each `Delivery`, one per recipient, carries it. A
`Mailpiece` is the mail log's row, a delegated type over `InboundEmail` and
`Delivery`, and `docs/lifecycle.md` says what each status means. Raw mail is an
attachment purged after `RETENTION_DAYS`; the row and its events stay. The
phrase a message was withheld for is for admins only.

## Interface

Sign in, signup, join, passkeys and access tokens are shared with sibling apps,
so change them in step. The stylesheets and Stimulus controllers that come from
the shared shell stay as they are, and our rules go in a file beside them
(`site-corners.css`, `site-print.css`). Views use English literals, by design.

## Coding style

Before editing or reviewing code, read STYLE.md.
