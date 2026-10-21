# Deployment & operations

PostRider is one self-hosted app — the web UI and the SMTP listeners running together on a single host. Under the hood it's an ordinary Rails app built into one image, and [Kamal](#deploying-with-kamal) is the way to install it: it deploys your own fork from your machine, with the web UI kept up across deploys. To run one container on one server without Kamal, use [Docker](#deploying-with-docker). [ONCE](#deploying-with-once), Basecamp's self-hosting tool, runs it too, with the limits listed there.

Here's what PostRider needs from you:

- **A persistent volume** for its SQLite database and stored email (Active Storage).
- **Inbound and submission ports** reachable from the internet (see [Ports](#ports)).
- **A few environment variables** — at minimum `SECRET_KEY_BASE` and either `RELAY_HOSTNAME` or `BASE_URL`.

**TLS for mail is handled by the app.** It obtains and renews its own Let's Encrypt certificate for the mail hostnames, and it answers the DNS challenge itself: a small DNS responder on port 53 serves `_acme-challenge.<hostname>` and nothing else. The one thing to do is publish an NS record per mail hostname delegating that name to the relay (see [TLS certificate](#tls-certificate)); from then on the app issues and renews on its own, with no API token and no DNS provider involved.

Once it's up, [Installation](installation.md) walks you through first sign-in, verifying a domain, and sending your first message — including the DNS records to publish.

## Before you start

- **Open the ports**, in your provider's firewall or security group: 80 and 443 for the web UI, 25 and 587 for mail, 53 UDP and TCP for the certificate challenge.
- **Outbound port 25.** Many providers block it on new servers until you ask support to lift it. Until then nothing can be delivered.
- **PTR** (reverse DNS) for the server's IP is set at your provider, not in your zone. Point it at `RELAY_HOSTNAME`.
- **IPv4 only.** Don't publish an AAAA record for the relay's hostnames: mail arriving over IPv6 would find nothing listening.

## Deploying with Kamal

Kamal deploys your own fork from your machine. `config/deploy.yml` is a starter for one server: set the server under each role's `hosts`, your web hostname under `proxy.host`, and `BASE_URL`. Secrets are read from your environment by `.kamal/secrets` (`SECRET_KEY_BASE` and `RELAY_PUBLIC_IP`), so export them, or swap the lines for your password manager. Then:

```bash
bin/kamal setup     # the first time
bin/kamal deploy    # from then on
```

The host runs three roles from one image, so the web UI, the jobs and the SMTP listeners deploy and fail independently:

- **`web`** — the web UI alone (`SOLID_QUEUE_IN_PUMA=false`), behind kamal-proxy, which terminates TLS for your web hostname.
- **`jobs`** — runs `bin/jobs`: deliveries, forwarding, webhooks and the sweeps, from `config/queue.yml`.
- **`smtp`** — runs `bin/relay` with `RELAY_IN_PUMA=false`, so the SMTP listeners run on their own rather than inside Puma. It publishes the mail ports (`25:25`, `587:587`) and the ACME DNS port (`53:53`, `53:53/udp`) on `RELAY_PUBLIC_IP`.

`web` and `jobs` roll over without a gap. `smtp` can't: two containers can't both hold port 25, so `.kamal/hooks/pre-app-boot` stops the old one before the new one boots, and SMTP is down for that moment.

More than one environment? Put each in an overlay, `config/deploy.<name>.yml`, with its secrets in `.kamal/secrets.<name>`, and deploy with `bin/kamal deploy -d <name>`.

For day-to-day work, use the bundled aliases: `bin/kamal console`, `bin/kamal shell`, `bin/kamal logs`.

### Litestream backups (optional)

[Litestream](https://litestream.io) can stream the four databases to an S3-compatible bucket, as an accessory beside the app. The starter `config/deploy.yml` doesn't set it up; to add it, put the accessory and two aliases in `config/deploy.yml`:

```yaml
accessories:
  litestream:
    image: litestream/litestream:0.5.17
    roles:
      - web
    cmd: replicate
    files:
      - config/litestream.yml:/etc/litestream.yml
    options:
      # The uid that owns /rails/storage in the app's image.
      user: "1000:1000"
      # Litestream uploads the last hour as it stops, and docker kills it after 10 seconds by default.
      stop-timeout: 60
    volumes:
      - "postrider:/rails/storage"
    env:
      clear:
        LITESTREAM_BUCKET: my-postrider-backups
      secret:
        - LITESTREAM_ACCESS_KEY_ID
        - LITESTREAM_ENDPOINT
        - LITESTREAM_SECRET_ACCESS_KEY

aliases:
  # beside console, shell and logs
  restore-check: accessory exec litestream "restore -o /rails/storage/restored.sqlite3 /rails/storage/production.sqlite3"
  backups: accessory exec litestream "ltx -level all /rails/storage/production.sqlite3"
```

The three roles share one server and one volume, so the accessory goes on the `web` role's host and runs there once. Add its secrets to `.kamal/secrets`:

```bash
LITESTREAM_ACCESS_KEY_ID=$LITESTREAM_ACCESS_KEY_ID
LITESTREAM_ENDPOINT=$LITESTREAM_ENDPOINT
LITESTREAM_SECRET_ACCESS_KEY=$LITESTREAM_SECRET_ACCESS_KEY
```

Then write `config/litestream.yml`, one entry per database:

```yaml
sync-interval: 60m
l0-retention-check-interval: 1h
levels:
  - interval: 1h
  - interval: 6h
  - interval: 24h

dbs:
  - path: /rails/storage/production.sqlite3
    replica:
      type: s3
      bucket: $LITESTREAM_BUCKET
      path: production
      endpoint: $LITESTREAM_ENDPOINT
      region: auto
  - path: /rails/storage/production_queue.sqlite3
    replica:
      type: s3
      bucket: $LITESTREAM_BUCKET
      path: production_queue
      endpoint: $LITESTREAM_ENDPOINT
      region: auto
  - path: /rails/storage/production_cable.sqlite3
    replica:
      type: s3
      bucket: $LITESTREAM_BUCKET
      path: production_cable
      endpoint: $LITESTREAM_ENDPOINT
      region: auto
  - path: /rails/storage/production_cache.sqlite3
    replica:
      type: s3
      bucket: $LITESTREAM_BUCKET
      path: production_cache
      endpoint: $LITESTREAM_ENDPOINT
      region: auto

# A restore reaches back fifteen days.
snapshot:
  retention: 360h
```

`bin/kamal setup` starts it with the app. On a server that's already running, start it with `bin/kamal accessory boot litestream`. Checking and restoring are under [With Kamal](#with-kamal) in Backups.

## Deploying with Docker

Without Kamal, PostRider runs as one container on one server. The repo isn't published as an image yet, so build it from a clone on the server:

```bash
git clone git@github.com:mailpiece/postrider.git
cd postrider
docker build -t postrider .
```

Settings live in an env file, `postrider.env`, in the clone next to `compose.yml`. Keep it private — it holds the secret every encrypted column is keyed from:

```bash
touch postrider.env && chmod 600 postrider.env
```

```ini
BASE_URL=https://mail.example.com
TLS_DOMAIN=mail.example.com
SECRET_KEY_BASE=<openssl rand -hex 64>
```

`TLS_DOMAIN` is the web UI's host: Thruster, in front of Puma inside the container, gets its Let's Encrypt certificate on 80 and 443. The relay takes its hostname from `BASE_URL` unless you set `RELAY_HOSTNAME`.

Ports 25, 587 and 53 are published on the server's own address alone (see [TLS certificate](#tls-certificate) for why). Find it with:

```bash
IP=$(ip -4 route get 1.1.1.1 | sed -n 's/.* src \([0-9.]*\).*/\1/p')
```

Then run it:

```bash
docker run -d --restart unless-stopped --stop-timeout 30 \
  -p 80:80 -p 443:443 \
  -p $IP:25:25 -p $IP:587:587 -p $IP:53:53 -p $IP:53:53/udp \
  -v postrider:/rails/storage \
  --env-file postrider.env \
  --name postrider postrider
```

The web UI, the jobs and the SMTP listeners all run in that one container.

Rather use Compose? [`compose.yml`](../compose.yml) is the same container. It reads `postrider.env` too, and takes the address from `.env`:

```bash
echo "RELAY_PUBLIC_IP=$IP" > .env
docker compose up -d
```

For a console, `docker exec -it postrider bin/rails console` (`docker compose exec postrider bin/rails console` under Compose).

To update, pull and rebuild, then replace the container:

```bash
git pull
docker build -t postrider .
docker stop postrider && docker rm postrider
# …and the same docker run as above
```

Under Compose that's `git pull` and `docker compose up -d --build`. Either way the web UI, the jobs and SMTP stop for the moment the new container takes to boot; sending servers retry, so inbound mail waits rather than bouncing.

Testing locally? Set `DISABLE_SSL=true` in place of `TLS_DOMAIN` to reach the web UI over plain HTTP.

## Deploying with ONCE

[ONCE](https://github.com/basecamp/once) runs an image on one server behind its own kamal-proxy. Push the image to a registry ONCE can pull from, then:

```bash
once deploy <image> --host mail.example.com
```

ONCE sets what PostRider needs:

- **`SECRET_KEY_BASE`**, generated by ONCE and kept with the app.
- **`BASE_URL`**, from the app's host. The relay takes its hostname from it unless you set `RELAY_HOSTNAME`, so web and mail share one name.
- **`DISABLE_SSL=true`**, only when TLS is off for the app.
- **The app's volume**, mounted at `/rails/storage`.
- **A health check** on `/up`.

The web UI, the jobs and the SMTP listeners all run inside Puma (`config/puma.rb`), so the one container ONCE runs is enough. Any other variable from [Configuration](#configuration-env) goes in with `--env KEY=VALUE`.

ONCE's SMTP settings are not used: PostRider sends its own mail through itself. Only the from address reaches the app, as `MAILER_FROM_ADDRESS`, the support address shown on the sign-in and forwarding confirmation pages.

**Keep TLS on.** Sign-in is by passkey only, and browsers offer passkeys only over HTTPS or on localhost. Give the app a hostname and leave TLS on.

**Changing the host breaks every passkey.** A passkey is bound to the hostname it was created on. After the app's host changes in ONCE, no existing passkey works, and everyone signs in again through the [console recovery lines](installation.md#1-create-the-first-account).

For a console:

```bash
once exec mail.example.com bin/rails console
```

Under ONCE, use its own backup and restore. It pauses the container while it copies the volume, so the databases are at rest, and resumes it afterwards.

**Inbound mail and submission don't work on ONCE yet.** ONCE publishes only HTTP and HTTPS, through kamal-proxy, so ports 25, 587 and 53 (TCP and UDP) are not reachable on a stock install. Without 53 the relay can't get its mail certificate, and the MX and submission listeners wait for it. The web UI, the API, outbound sending and the jobs work.

Once ONCE can publish those ports, the host needs what [Before you start](#before-you-start) lists: 80, 443, 25, 587 and 53 TCP and UDP open, outbound 25 allowed by your provider, and PTR set. ONCE publishes ports on every address, not on `RELAY_PUBLIC_IP` alone as the Docker and Kamal setups do. On a host running systemd-resolved, its stub listener already holds port 53, so turn it off with `DNSStubListener=no` in `/etc/systemd/resolved.conf`.

## Backups

Everything lives in the `postrider` volume.

### With Kamal

Litestream, set up as in [Litestream backups](#litestream-backups-optional), streams `production.sqlite3`, `production_queue.sqlite3`, `production_cable.sqlite3` and `production_cache.sqlite3` to `LITESTREAM_BUCKET`, keeping fifteen days.

Raw mail and attachments are not copied. They live in Active Storage on the volume (`ACTIVE_STORAGE_SERVICE` is `local`), and Litestream copies only the databases. `RETENTION_DAYS` deletes them anyway, so a Litestream restore brings back the mail log, the domains and the settings, without the raw mail of the days before.

Keep `SECRET_KEY_BASE` apart from the server too: without it the DKIM and ARC keys, the certificate and the webhook secrets in the databases can't be read.

`backups` and `restore-check` are the aliases from `config/deploy.yml`. `restore-check` writes `restored.sqlite3` beside the live database. Delete it afterwards; a second run refuses to overwrite it.

```bash
bin/kamal backups         # every backup file, with time and size
bin/kamal restore-check   # latest backup into restored.sqlite3
```

### Restoring with Kamal

Keep the old server off, or two machines write to the same bucket. Never use `kamal setup` to bring a server back: it backs up empty databases on top of your history.

Deploy first, then stop the app and Litestream. `bin/kamal app stop` stops all three roles, so `smtp` lets go of port 25 and nothing writes while the databases move. Move them to `/rails/storage/aside`, hand Litestream its config and restore the four. To restore to a moment instead, add `-timestamp 2026-10-06T17:15:00Z` after `restore`.

```bash
bin/kamal server bootstrap   # a new server only
bin/kamal deploy

bin/kamal app stop
bin/kamal accessory stop litestream
bin/kamal app exec --roles web \
  "bash -c 'mkdir /rails/storage/aside && mv /rails/storage/production*.sqlite3* /rails/storage/aside/ && rm -rf /rails/storage/.production*.sqlite3-litestream'"

bin/kamal accessory reboot litestream
bin/kamal accessory stop litestream
for db in production production_queue production_cable production_cache; do
  bin/kamal accessory exec litestream "restore -integrity-check quick /rails/storage/$db.sqlite3"
done

bin/kamal app start
```

Check the data before starting Litestream again with `bin/kamal accessory start litestream`, then delete `aside`. If the data is wrong, stop the app and move the files in `aside` back.

### With Docker

Stop the container so the databases are at rest, archive the volume to a file on the host, and start it again:

```bash
docker stop postrider
docker run --rm \
  --user root \
  --volume postrider:/rails/storage \
  --volume "$PWD":/backup \
  postrider \
  tar czf "/backup/postrider-backup.tar.gz" -C /rails storage
docker start postrider
```

Mail sent to the relay while it's stopped is retried by the sending servers. Copy the archive somewhere safe, ideally off the machine. To restore, stop the container, extract the archive back into the volume and start it:

```bash
docker stop postrider
docker run --rm \
  --user root \
  --volume postrider:/rails/storage \
  --volume "$PWD":/backup \
  postrider \
  tar xzf "/backup/postrider-backup.tar.gz" -C /rails
docker start postrider
```

> [!WARNING]
> Back up `postrider.env` separately. Without its `SECRET_KEY_BASE` the DKIM and ARC keys, the certificate and the webhook secrets in the backup can't be read.

A backup also keeps mail past `RETENTION_DAYS`: the sweep incinerates mail in the live volume, not in archives you've taken.

## Ports

| Listener   | Purpose                                          | Port         |
| ---------- | ------------------------------------------------ | ------------ |
| MX         | Inbound mail from the internet                   | 25           |
| Submission | Authenticated mail from clients                  | 587          |
| ACME DNS   | Let's Encrypt reads the certificate challenge    | 53 UDP + TCP |

The listeners bind 25, 587 and 53 inside the container, and the Dockerfile `EXPOSE`s them; publish them on `RELAY_PUBLIC_IP` as above. Development uses 2525, 2587 and 2553 instead (bin/dev on a Mac cannot bind 25 or 53, and 5353 belongs to mDNS). `MX_PORT` / `SUBMISSION_PORT` / `ACME_DNS_PORT` override any of them.

## Submission & authentication

Point mail clients at the submission listener on **port 587 with STARTTLS**. That's the only submission transport: there's no implicit-TLS (SMTPS) listener on 465, so a client configured for 465 will fail to connect rather than quietly falling back. Encryption isn't optional — the listener refuses `AUTH`, `MAIL FROM`, and everything after until the client has issued `STARTTLS`.

Both `AUTH PLAIN` and `AUTH LOGIN` work (advertised as `250-AUTH PLAIN LOGIN`), and they're equivalent — same secret, same TLS requirement — so your client can use whichever it defaults to. Challenge-response mechanisms like CRAM-MD5 aren't offered and never can be, because sending tokens are only stored as a hash.

The password is a **sending token**, generated per domain in the tenant UI. The username is purely cosmetic — only the token is checked, so any username works (the convention is `postrider`). Rotating is painless: create a new token, cut the client over, delete the old one. Since a domain can have multiple live tokens, there's no downtime.

> [!NOTE]
> `PIPELINING` isn't supported, deliberately: a second command arriving before its reply gets a `500`, on both listeners. That's what keeps a command smuggled in the clear behind `STARTTLS` from ever reaching the parser.

## Configuration (ENV)

Every variable PostRider reads, A–Z. Provide them however your deployment does: `postrider.env`, Kamal, systemd. Two are **required**: `SECRET_KEY_BASE`, and a hostname for the relay (`RELAY_HOSTNAME`, or failing that the host of `BASE_URL`, which is what an install with web and mail on one name runs on). And keep the secrets (`SECRET_KEY_BASE`, `POSTHOG_API_KEY`) out of version control. DKIM and ARC keys, the certificate, the ACME account key and webhook signing secrets are encrypted with a key derived from `SECRET_KEY_BASE`; rotating it means new DKIM and ARC keys published in DNS, a reissued certificate and new webhook secrets. Email addresses are stored plain.

| Variable | Default | Purpose |
| --- | --- | --- |
| `ACME_CONTACT` | — | Optional contact email for the ACME account |
| `ACME_DIRECTORY` | Let's Encrypt production | Where certificates are issued from. Point it at Let's Encrypt staging to test issuance without burning rate limits |
| `ACME_DNS_PORT` | `53` (`2553` in development) | Port the ACME DNS responder listens on, UDP and TCP (see [TLS certificate](#tls-certificate)) |
| `ACTIVE_STORAGE_SERVICE` | `local` | Where raw email blobs live. Set in `config/environments/production.rb` |
| `ASSUME_SSL` | on | Treat requests as HTTPS, for secure cookies behind a TLS-terminating proxy. Use `DISABLE_SSL=true` for plain HTTP |
| `BASE_URL` | none | The public URL of your PostRider instance, e.g. `https://postrider.example.com`. Set it: a mailbox forwarding confirmation carries a link to it, so it cannot be sent without it. The sign-in link printed from the console is built from it too |
| `BIND_ADDRESS` | `0.0.0.0` | Address both listeners bind to |
| `DELIVERY_JOB_CONCURRENCY` / `WEBHOOK_JOB_CONCURRENCY` / `FORWARDING_JOB_CONCURRENCY` | `2` / `1` / `1` | Per-queue job concurrency (`config/queue.yml`) |
| `DISABLE_SSL` | — | Set `true` to turn off all SSL options at once (`assume_ssl` + `force_ssl`) — for serving the web UI over plain HTTP with no proxy |
| `FORCE_SSL` | on | Redirect HTTP→HTTPS, enable HSTS and secure cookies. Needs a TLS proxy in front (or `DISABLE_SSL=true`) |
| `HELO_HOSTNAME` | `RELAY_HOSTNAME` | HELO/EHLO name for outbound delivery; override only if it should differ |
| `INBOUND_MAX_MESSAGE_SIZE` | `26214400` (25 MB) | Reject larger inbound (MX) messages at the listener |
| `MAILER_FROM_ADDRESS` | none | Support address shown on the sign-in and forwarding confirmation pages, and in the confirmation mail. Only the address is used. PostRider sends its own mail from `noreply@<domain>` through itself, so it needs no outside mail account |
| `MTA_STS` | — | Set `true` to enforce RFC 8461 MTA-STS on outbound delivery (see [MTA-STS](#mta-sts)) |
| `MULTI_TENANT` | `false` | Multi-tenant signups; keep `false` for a self-hosted install |
| `MX_MAX_CONNECTIONS` / `SUBMISSION_MAX_CONNECTIONS` | `50` | Concurrent connections each listener accepts |
| `MX_MAX_CONNECTIONS_PER_IP` / `SUBMISSION_MAX_CONNECTIONS_PER_IP` | `10` / `30` | Concurrent connections from a single IP |
| `MX_MAX_PROCESSINGS` / `SUBMISSION_MAX_PROCESSINGS` | `10` | Messages processed concurrently per listener. Also sizes the database pool |
| `MX_MAX_RECIPIENTS` | `50` | Recipients per inbound SMTP transaction; further `RCPT TO`s get a `452` |
| `MX_PORT` | `25` (`2525` in development) | Inbound listener port |
| `OUTBOUND_MAX_MESSAGE_SIZE` | `10485760` (10 MB) | Reject larger outbound (submission) messages at the listener |
| `OUTBOUND_RELAY` | — | `host:port` to relay all outbound mail through, bypassing MX resolution. Handy as a hosted-relay escape hatch or a local dev sink |
| `POSTHOG_API_KEY` | — | PostHog project token for error tracking. Leave unset to turn it off |
| `POSTHOG_HOST` | `https://us.i.posthog.com` | PostHog endpoint; change for EU cloud or self-hosted |
| `RAILS_LOG_LEVEL` | `info` | Rails log verbosity |
| `RELAY_HOSTNAME` | host of `BASE_URL` | This server's public hostname — MX target, TLS certificate name, and PTR/HELO name. Every record the app tells you to publish is generated from it. Set it when mail answers on a different name than the web UI; unset, the relay takes the host of `BASE_URL`, and one of the two is required |
| `RELAY_MAIL_DOMAIN` | `RELAY_HOSTNAME` | The relay's outbound identity: domain of the relay-owned VERP bounce Return-Path (`bounces+…@…`) used by every domain that hasn't set up a custom one, and the target each domain's `mailer.<domain>` CNAME points at. It needs an MX pointing at the relay (self-MX when it equals `RELAY_HOSTNAME`). Set it to a name of its own — see [Sending identity](#sending-identity) |
| `RELAY_PUBLIC_IP` | — | Deploy-time, read by `config/deploy.yml` and `compose.yml`: the server's own address ports 25, 587 and 53 are published on, and the only one they answer on — the private one behind NAT (AWS and the like). Kamal takes it from `.kamal/secrets`, Compose from `.env` |
| `REQUIRE_TLS_MX_SUFFIXES` | — | Comma-separated MX hostname suffixes that must be reached over verified TLS: the certificate has to validate against the MX name, and a failure defers delivery instead of falling back to plaintext. Unset means no enforcement. `.google.com,.outlook.com` covers the providers carrying most transactional mail; leading dots are added if you leave them off |
| `RETENTION_DAYS` | `30` | Days before raw content and attachments are deleted (metadata rows stay) |
| `SECRET_KEY_BASE` | — | Rails secret key base. Generate one with `bin/rails secret` |
| `SENDING_IPS` | — | Comma-separated `name=address=helo` list of source IPs for direct-to-MX delivery. The first entry is the default every send binds to for now; each address needs matching PTR/rDNS for its HELO name. Unset = the host's default IP |
| `SMTP_LOG_LEVEL` | `INFO` | Listener log verbosity. `DEBUG` logs the full SMTP conversation line by line (AUTH credentials are redacted, but it's still verbose) — keep it off in production and access-controlled. Read once at boot, so changing it means restarting the listeners |
| `STRUCTURED_LOGGING` | — | Set `true` to also write each Rails event (requests, jobs, mail) to stdout as a line of JSON, for a log shipper to index. SQL and view events are left out |
| `SUBMISSION_HOSTNAME` | `RELAY_HOSTNAME` | What clients configure as their outgoing SMTP server — the submission listener's banner/Received identity |
| `SUBMISSION_PORT` | `587` (`2587` in development) | Submission listener port |
| `SUBMISSION_RATE_LIMIT` | `30` | Submissions per account per minute |
| `TRUSTED_PROXIES` | — | Comma-separated CIDR ranges whose `X-Forwarded-For` entries are trusted, on top of the private network ranges Rails trusts already (see [Client IP](#client-ip)) |

## Client IP

`request.remote_ip` drives IP rate limiting and the IP stamped on each session. Rails reads it from the `X-Forwarded-For` chain, taking the rightmost entry that isn't a trusted proxy.

> [!WARNING]
> If you run PostRider behind a proxy or CDN, set `TRUSTED_PROXIES` to that proxy's IP ranges and make sure the proxy forwards the client's real address. Miss that and every visitor behind one edge shares a single rate-limit bucket.
>
> With kamal-proxy specifically, also set `forward_headers: true` in the `proxy:` block. Without it, kamal-proxy drops the `X-Forwarded-For` chain entirely, `remote_ip` becomes the edge address, and everyone behind that PoP shares one bucket.

## DNS

Each domain you register shows the exact records to publish — inbound MX (or CNAME), DKIM, optional DMARC and Return-Path — and checks them against live DNS from its own page, so follow that. Two things sit outside any single domain:

- `RELAY_HOSTNAME` needs an A/AAAA record, a self-MX, and one relay-wide SPF record (`<RELAY_HOSTNAME>. TXT "v=spf1 a:<RELAY_HOSTNAME> -all"`) so relay-owned bounce Return-Paths authenticate.
- `_acme-challenge.<mail hostname>` needs an NS record pointing at `RELAY_HOSTNAME`, one per hostname in `Relay.tls_hostnames`, so Let's Encrypt reads the certificate challenge from the relay (see [TLS certificate](#tls-certificate)).
- Your host must set **PTR** (reverse DNS) for the server's IP to `RELAY_HOSTNAME`.
- `arc._domainkey.<RELAY_MAIL_DOMAIN>` needs the TXT record shown under Server Settings, so receivers can check the ARC seal on forwarded mail (see [Forwarded mail](#forwarded-mail)).

**Check DNS now** under Server Settings verifies A/AAAA, SPF, PTR, the certificate delegation and the ARC sealing key for you.

### Sending identity

`RELAY_MAIL_DOMAIN` defaults to `RELAY_HOSTNAME`, which puts your inbound MX and your outbound identity on one name. That works, but it welds them together: every domain's `mailer.<domain>` CNAME points at it, so the address behind that name can never change without every customer editing DNS. One customer's sending reputation then rides on the same address that receives everyone's mail.

Give sending its own name before the first domain is registered:

```
RELAY_MAIL_DOMAIN=mailer.example.com
```

and publish, alongside the `RELAY_HOSTNAME` records above:

| Record | Value | Why |
|---|---|---|
| `mailer.example.com` A/AAAA | the sending address | What `mailer.<domain>` CNAMEs resolve to |
| `mailer.example.com` TXT | `v=spf1 a:mailer.example.com -all` | Authenticates Return-Paths under that name |
| `mailer.example.com` MX | `10 <RELAY_HOSTNAME>.` | Routes bounces back to the relay |
| `arc._domainkey.mailer.example.com` TXT | the value shown under Server Settings | Publishes the key forwarded mail is ARC-sealed with |
| PTR for the sending address | `mailer.example.com` | Receivers check forward-confirmed reverse DNS |

Point it at the same server as `RELAY_HOSTNAME` to start — nothing changes operationally. The gain is later: moving outbound to its own address is then one A record in your zone, and no customer touches anything.

Changing `RELAY_MAIL_DOMAIN` after domains exist invalidates their Return-Path checks until each republishes its `mailer.<domain>` CNAME, so pick the name up front.

### Forwarded mail

Forwarding breaks authentication by design: SPF fails at the new hop, and DKIM fails the moment anything downstream touches the message. Signing the forward with the customer's DKIM key doesn't fix that — the `From:` belongs to whoever wrote the mail, not to your customer, so a signature from their domain proves nothing under DMARC and has them vouching for mail they never sent.

PostRider seals forwards with the relay's own key instead, as one ARC set (RFC 8617): an `ARC-Authentication-Results` recording what this relay concluded when the mail arrived, an `ARC-Message-Signature` over the message, and an `ARC-Seal` over the chain. Receivers that evaluate ARC can then see that the mail authenticated here before you passed it on. A domain that only forwards never has to publish DKIM — its page reads "Not verified for sending", which is exactly what it means.

The sealing key is generated on first use and stored encrypted in the database, like the TLS certificate; there is no ENV variable for it. Publish it at `arc._domainkey.<RELAY_MAIL_DOMAIN>` using the value on the Server Settings page. Until you do, forwards still go out, and **Check DNS now** reports the sealing key as missing without marking the relay unready.

## TLS certificate

Both listeners offer STARTTLS, and the app obtains and renews its own Let's Encrypt certificate for every hostname in `Relay.tls_hostnames`, hot-swapped into the running listeners with no restart. The hostnames are proven over DNS (`dns-01`), and the app answers that query itself: a responder on port 53 (`ACME_DNS_PORT`) serves `_acme-challenge.<hostname>` from the certificate row and refuses every other name. No API token, no DNS provider, no port 80.

Your part is one NS record per mail hostname and port 53 open inbound, UDP and TCP. With `RELAY_HOSTNAME=mx.example.com` and `SUBMISSION_HOSTNAME=smtp.example.com`:

```
_acme-challenge.mx.example.com.    NS  mx.example.com.
_acme-challenge.smtp.example.com.  NS  mx.example.com.
```

Ports 25, 587 and 53 are published on the server's own address (`RELAY_PUBLIC_IP`), not on every address: mail and DNS answer there alone, a Tailscale or other interface on the same box stays closed, and systemd-resolved's stub on `127.0.0.53` is never in the way. Behind NAT (AWS and the like) that's the private address the public one forwards to. The listeners bind 25, 587 and 53 as an unprivileged user, which Docker allows inside a container and host networking does not.

**Server Settings** has a **TLS certificate** screen with the current certificate, the delegation's status and **Renew now**; the **DNS records** screen lists the NS records and checks that each resolves to the relay. Renewal runs on boot and hourly. It looks the challenge record up through public DNS before asking Let's Encrypt, and fails with the record to publish until the delegation resolves. `bin/dev` uses a self-signed certificate and does none of this.

## Outbound TLS

Delivery to other mail servers uses opportunistic STARTTLS: encrypted where the receiver offers it, plaintext where it doesn't, certificates unverified either way. That's what every mainstream MTA does — plenty of receiving servers present self-signed, expired, or mismatched certificates, and demanding verification everywhere would fail a lot of legitimate mail.

The catch is that opportunistic TLS folds under pressure. An attacker on the network path can force plaintext by breaking the handshake, or by stripping the `STARTTLS` advertisement from the greeting — and that one succeeds silently, with no error at all.

Two mechanisms close the gap: a static suffix list you set, and [MTA-STS](#mta-sts) policies that destinations publish themselves. `REQUIRE_TLS_MX_SUFFIXES` names the destinations where the plaintext trade-off isn't acceptable: for any MX hostname ending in a listed suffix, PostRider verifies the certificate against the MX name and refuses to fall back — a TLS failure defers the delivery and retries it for the usual two days.

Google and Microsoft carry most transactional mail, and both publish MTA-STS policies asking senders to do exactly this, so they're the sensible starting point:

```
REQUIRE_TLS_MX_SUFFIXES=.google.com,.outlook.com
```

`.google.com` covers Gmail and Google Workspace (`gmail-smtp-in.l.google.com`, `aspmx.l.google.com`); `.outlook.com` covers Outlook, Hotmail, and Microsoft 365 (`*.mail.protection.outlook.com`, `*.olc.protection.outlook.com`).

> [!WARNING]
> Unset means no enforcement from this list. Nothing is required by default — only you know whether your network reaches every listed provider over TLS. MTA-STS below works independently.

A few other things worth knowing:

- Suffixes match the **MX hostname**, not the recipient domain, and a leading dot is added if you leave it off. Without the dot, `google.com` would also match `notgoogle.com`.
- `OUTBOUND_RELAY` is exempt: enforcement applies to port 25 only, so your own smarthost on a custom port can keep its self-signed certificate.
- The list is the manual floor, not the whole mechanism. With `MTA_STS=true`, domains that publish a policy get verified TLS automatically, listed or not — so the list earns its keep for destinations without a policy, and a provider moving its MX names off a listed suffix doesn't silently end enforcement.

### MTA-STS

Destinations that publish an [MTA-STS](https://www.rfc-editor.org/rfc/rfc8461) (RFC 8461) policy get the same verified-TLS treatment automatically — no list to maintain. It's off by default; set `MTA_STS=true` to turn it on.

On each delivery, PostRider looks up the destination's `_mta-sts` TXT record, fetches the policy over HTTPS, and caches it in the database, refreshing when the record advertises a new policy id. The cache is what resists downgrade: once a policy is stored, a vanished TXT record or a failed refresh never weakens it — it stands until its own `max_age` runs out, and only a validated new policy replaces it. An attacker who can drop DNS answers or block the HTTPS fetch gains nothing against a domain you've delivered to before. A daily task re-checks every cached policy, so enforcement doesn't lapse for domains you rarely send to, and purges entries long past expiry.

When a policy's mode is `enforce`, delivery goes only to MX hosts matching the policy's `mx` patterns, over TLS verified against the MX hostname, and a server that doesn't offer `STARTTLS` is refused. Any TLS failure defers the delivery — retried for the usual two days — rather than falling back to plaintext. `testing` and `none` policies change nothing: `testing` is meant to be observed through TLSRPT reports, which PostRider doesn't send, so for us it's a no-op.

The scope matches the suffix list: direct-to-MX delivery on port 25 only, `OUTBOUND_RELAY` exempt. The two compose — whichever demands TLS for a destination wins — so keep `REQUIRE_TLS_MX_SUFFIXES` as your floor for providers that publish no policy.

Two limits worth knowing. Trust roots in the policy host's HTTPS certificate, not DNSSEC — that's the RFC's design — which means the TXT lookup itself is unauthenticated, and the cache is your only defense the first time you deliver to a domain. And this is the sending half only: PostRider doesn't publish an MTA-STS policy for your own inbound mail.