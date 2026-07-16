# Out of Scope Features

- Universal links (requires Sourcehut to host an apple-app-site-association
  file)
- Push notifications for builds and tickets (requires a backend relay server)
  - ref: https://git.sr.ht/~ccleberg/hutch-notify
- Explore / search (hub.sr.ht) (no public discovery API)
- Pronouns on profile (not in GraphQL schema)
- Revoke personal access tokens (`@internal` in schema, inaccessible)
- Archive a message to a list (`archiveMessage` is `@internal`, inaccessible)
- Subscribe to a mailing list (`mailingListSubscribe` exists, but `MailingList`
  has no `subscription` field and sr.ht has no discovery API, so there is no way
  to find a list you are not already subscribed to — see hub.sr.ht above)
- Submitting patches (a `git send-email` flow, not a GraphQL mutation; Hutch
  reviews patchsets but cannot send them)

## Declined rather than blocked

These are reachable in the API. They are left out on judgement, not capability.

- **Webhook management** (24 fields across five services). A webhook needs an
  HTTPS endpoint you control to receive POSTs. Without the relay above, this
  only serves someone already running their own endpoint, and that person is not
  managing it from a phone. Reconsider if `hutch-notify` ever ships.
- **`shareSecret`.** Shares a build secret — an SSH key or PAT — with another
  user. A mistap grants someone else a credential, and nothing in the app can
  take it back. That belongs on the web behind a full-size confirmation. The
  read-only `secrets` list would be fine on its own.
- **Build groups** (`createGroup`, `startGroup`). Multi-job pipelines are
  authored in `.build.yml`, not composed on a phone.
