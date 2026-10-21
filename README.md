# PostRider

PostRider is a self-hosted mail relay. It takes outbound mail over an HTTP API and SMTP submission and delivers it direct to MX with DKIM; it takes inbound mail on MX for the domains an account registers; and it reports what happened to each message through webhooks.

For anyone who wants deliverability without renting it: transactional mail a recipient is already expecting, apps that would rather run their own relay than integrate a SaaS sending provider, teams done paying rent on a problem they mostly don't have.

**PostRider** handles:

- outbound mail over an HTTP API and SMTP submission, signed with DKIM and delivered direct to MX
- inbound mail on MX for the mailboxes, or the catch-all, of the domains you register
- forwarding from a mailbox to another address, ARC-sealed with the relay's own key, for approved and authenticated senders
- webhooks for inbound mail and delivery events, signed per webhook
- its own TLS certificate, issued and renewed over ACME
- no reputation score, no warm-up schedule, no pricing tier

> Ship the email. Trust that the people who want it will find it.



## Contents

- [Deliverability Is Overrated](#deliverability-is-overrated)
- [Why Run Your Own?](#why-run-your-own)
- [Ship the Email](#ship-the-email)
- [Installation](docs/installation.md)
- [API (HTTP & SMTP sending)](docs/api.md)
- [Webhooks](docs/webhooks.md)
- [Statuses & Lifecycle](docs/lifecycle.md)
- [Development](docs/development.md)
- [Deployment & Operations](docs/deployment.md)
- [History](#history)
- [Contributing](#contributing)
- [License](#license)



## Deliverability Is Overrated

Not the concept. The panic.

Somewhere along the way, "send an email" became a SaaS category. Dashboards. Reputation scores. Warm-up schedules. Pricing tiers built around inbox placement. All of it makes sense if you're blasting newsletters at people who never asked. Most email isn't that. Most email is something a person is actually waiting for.

Take the clearest case: a password reset, sent to someone who signed up ninety seconds ago and is staring at their inbox right now. That person isn't a cold prospect. They're mid-task. They triggered the email. They want the email. If it's not in the inbox, they'll check spam without a second thought. The context does the deliverability work for you — you just have to stop getting in its way. And the same holds, to varying degrees, for most of the mail you send: notifications, receipts, updates, the message that lands because someone was expecting it.

So PostRider is a bet: run your own relay, keep it clean, do the fundamentals, and stop paying rent on a problem you mostly don't have. In real use, the bet holds. Mail lands.

Outlook is still Outlook and occasionally has opinions. So do the people you're paying to avoid it.

## Why Run Your Own?

Because you can. That used to be reason enough. It still is.

## Ship the Email

Ship the email. Trust that the people who want it will find it. Then go spend your engineering time on your actual product instead of babysitting a sender score.

## History

View the [changelog](CHANGELOG.md).

## Contributing

See [CONTRIBUTING](CONTRIBUTING.md). To report a vulnerability, see [SECURITY](SECURITY.md).

## License

MIT. See [MIT-LICENSE](MIT-LICENSE).