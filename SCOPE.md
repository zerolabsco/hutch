# Out of Scope Features

- Universal links (requires Sourcehut to host an apple-app-site-association
  file)
- Push notifications for builds and tickets (requires a backend relay server)
  - ref: https://git.sr.ht/~ccleberg/hutch-notify
- Explore / search (hub.sr.ht) (no public discovery API)
- ~~Pronouns on profile (not in GraphQL schema)~~ — **stale**. sr.ht added
  pronouns (see the Q1 2026 "What's cooking"), and Hutch already queries them in
  `AppState` and shows them in `UserProfileView`. Left here struck through as
  evidence for the ingestion task in ROADMAP.md: this entry spent months telling
  people not to build something that was already built.
- Revoke personal access tokens (`@internal` in schema, inaccessible)
- Archive a message to a list (`archiveMessage` is `@internal`, inaccessible)
- Ticket activity feed (todo.sr.ht's root `events` query is broken upstream and
  returns an empty list for every user). `event.participant_id` references
  `participant(id)`, but the resolver joins it against `participant.user_id`:

  ```sql
  FROM event ev
  JOIN participant p ON p.user_id = ev.participant_id   -- id space vs user id space
  WHERE p.user_id = <viewer>
  ```

  The rows exist — the writer inserts `participant.ID` for the submitter and for
  every subscriber — but that join cannot find them. `Ticket.events` is
  unaffected because it filters on `ev.ticket_id`, which is why ticket timelines
  work. Nothing a client can do fixes this; revisit only if sr.ht changes the
  resolver.
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
