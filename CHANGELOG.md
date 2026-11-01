# Changelog

## [Unreleased]

- Initial public release.
- The mailpiece viewer removes known spy pixels from inbound email, also when remote images are loaded, and names the services.
- A domain can keep a list of blocked phrases: mail submitted from it that contains one is kept but not delivered.
- Inbound attachments are stored without being opened by an image library; libvips is no longer required.
- A webhook's signing secret can be given when it is created and changed later, so a relay's password can be rotated without recreating the webhook.
- A domain's DNS records can be read as JSON, and the API docs cover mailboxes and webhooks.
