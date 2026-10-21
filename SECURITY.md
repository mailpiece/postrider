# Security

Report vulnerabilities to security@postrider.dev or at
https://github.com/mailpiece/postrider/security. Please don't open a public issue.

## Trust model

PostRider is self-hosted, so staff are the server operator, with shell, network, and
database access already. Anything requiring staff (`/adminland`: relay DNS, the
certificate, jobs) grants nothing they do not already have, and is not a vulnerability.

We do want reports of anything a non-staff user can reach beyond their own role and
domains, of mail leaving for a domain that did not authorize it, of a sending token,
DKIM key or webhook secret leaking, and of any credential or network path held by the
PostRider process but not by the operator's own shell.

## Intentional behavior

Webhook URLs are restricted, because any account admin picks the destination, so each one is
resolved through Surfguard and never called at a private or internal address.
