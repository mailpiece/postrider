# Development

```bash
bundle install
bin/setup     # creates the SQLite databases
bin/dev       # web on :3010, SMTP listeners on :2525 / :2587, ACME DNS on :2553
bin/rails test  # PARALLEL_WORKERS=1 to serialize
bin/ci          # Rubocop, audits, Brakeman, Gitleaks, tests, system tests
bin/jobs        # Solid Queue
```

The app answers at `http://app.postrider.localhost:3010` and the demo owner signs in as `mike@example.com`. In development the sign-in page lists everyone as **Sign in as** links, so you can skip the passkey. Plain `bin/dev` runs no jobs: use `bin/jobs`, or `touch tmp/solid-queue.txt`.

Out of the box, development runs the listeners on the default dev ports (`MX_PORT` 2525, `SUBMISSION_PORT` 2587, `ACME_DNS_PORT` 2553); production binds 25, 587 and 53, see [Ports](deployment.md#ports). Set up your domains, mailboxes, sending tokens, and webhooks in the admin UI.

## Dev Container

Prefer not to install Ruby and its dependencies locally? Open the repo in VS Code (or GitHub Codespaces) and the included [`.devcontainer/devcontainer.json`](../.devcontainer/devcontainer.json) hands you a ready-to-go environment. On first create it runs `bin/devcontainer`, which runs `bin/setup`, and forwards the web port (3010).
