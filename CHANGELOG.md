# Changelog

## [Unreleased]

- Initial public release.
- The mailpiece viewer removes known spy pixels from inbound email, also when remote images are loaded, and names the services.
- A domain can keep a list of blocked phrases: mail submitted from it that contains one is kept but not delivered.
- Inbound attachments are stored without being opened by an image library; libvips is no longer required.
