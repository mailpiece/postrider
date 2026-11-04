# PostRider

📮 A boring mail relay you run yourself.

Send and receive mail for your own domains from one self-hosted app. **PostRider** takes outbound mail over an HTTP API and SMTP submission and delivers it direct to MX with DKIM, takes inbound mail on MX for the domains an account registers, and reports what happened to each message through webhooks.

**PostRider** handles:

- outbound mail over an HTTP API and SMTP submission, signed with DKIM and delivered direct to MX
- inbound mail on MX for the mailboxes, or the catch-all, of the domains you register
- forwarding from a mailbox to another address, ARC-sealed with the relay's own key, for approved and authenticated senders
- webhooks for inbound mail and delivery events, signed per webhook
- its own TLS certificate, issued and renewed over ACME

Plus:

- a mail log of every message in both directions, with its history, in the app and over the [API](docs/api.md)
- sign-in by passkey only, so PostRider sends no sign-in mail
- no reputation score, no warm-up schedule, no pricing tier

> Ship the email. Trust that the people who want it will find it.



## Contents

- [Installation](#installation)
- [Getting Started](#getting-started)
- [Design](#design)
- [Interfaces](#interfaces)
- [Testing](#testing)
- [Contributing](#contributing)
- [License](#license)



## Installation

PostRider is a Rails app built into one image. It needs a persistent volume for its SQLite database and stored mail, ports 80 and 443 for the web UI, 25 and 587 for mail and 53 for the certificate challenge, outbound port 25, and at minimum `SECRET_KEY_BASE` and either `RELAY_HOSTNAME` or `BASE_URL`. Deploy your fork with Kamal:

```bash
bin/kamal setup     # the first time
bin/kamal deploy    # from then on
```

[Deployment & operations](docs/deployment.md) covers Kamal, Docker and ONCE; [Installation](docs/installation.md) takes it from first sign-in to a verified domain.

## Getting Started

Create a sending token on a verified domain's **Sending tokens** page, then send:

```bash
curl https://postrider.example.com/123456789/messages \
  -H "Authorization: Bearer $SENDING_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ "from": "hello@<domain>", "to": ["you@example.com"], "subject": "Hello", "text": "It works." }'
```

The path starts with your account's number, the one in the app's URLs. The same token is the password for SMTP submission on port 587, with STARTTLS.



## Design



### Mail: one log, both directions

A mailpiece is the mail log's row, over either an inbound email or a delivery. A message has no status of its own: each delivery, one per recipient, carries it, and [Statuses & lifecycle](docs/lifecycle.md) says what each one means. Raw mail is purged after `RETENTION_DAYS`; the row and its events stay.

### Tenancy: by URL, by domain

Each account lives under its number in the URL, and everything hangs off a domain, which a user sees only through an access. One install is one account; teammates join by invitation.

### Tokens: one domain each

A sending token sends only for its own verified domain, and only its digest is stored. Webhook secrets, DKIM keys and the certificate are encrypted columns. A forward is sealed with the relay's key, never signed with the tenant's.

### Roles: web, jobs and SMTP

Production runs the web app, the jobs and the SMTP listeners as separate roles. The certificate is issued over ACME by a small DNS responder in the app and swapped into the running listeners, so renewing it restarts nothing.

### Deliverability: the fundamentals

Most mail is something a person is waiting for: a password reset, a receipt, a notification they triggered. Keep the relay clean, sign with DKIM, publish SPF, DMARC and reverse DNS, and that mail lands without anyone renting deliverability.

## Interfaces

- [API](docs/api.md): sending over HTTP and SMTP, and reading the mail log, with sending tokens and personal access tokens.
- [Webhooks](docs/webhooks.md): signed events for inbound mail and deliveries, including Action Mailbox's relay format.
- [Statuses & lifecycle](docs/lifecycle.md): what each inbound and delivery status means.
- [Deployment & operations](docs/deployment.md): ports, configuration, DNS, the TLS certificate and backups.
- [Development](docs/development.md): running it locally and in a dev container.

## Testing

```sh
bin/setup
bin/rails test
bin/ci
```



## Contributing

Everyone is encouraged to help improve this project:

- Ask questions and suggest features in [discussions](https://github.com/mailpiece/postrider/discussions)
- Read [CONTRIBUTING](CONTRIBUTING.md) before opening an issue or pull request
- Report a vulnerability as [SECURITY](SECURITY.md) describes



## License

MIT. See [MIT-LICENSE](MIT-LICENSE).
