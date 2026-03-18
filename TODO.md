# Hutch TODO

## Claude Code, Codex, & Mistral Prompting Notes

- **Always start a new session with the project context block** (see
  hutch-ios-prompts.md prompt 0) so the agent knows the API conventions.
- **Keep prompts short and specific.** Long prompts waste context. One bug or
  feature per prompt. Paste console output and error messages directly instead
  of describing them.
- **When a fix fails twice, ask the agent to print raw state first** (raw API
  response, current file contents, exact variable values) before attempting
  another fix. Blind retries consume context without progress.
- **Never paste full file contents into the prompt.** Ask the agent to read
  the file itself using its file tools.
- **Batch only tightly related changes.** Unrelated changes in one prompt
  increase the chance of partial failure and wasted context on rollback.

## Features

- **Exact repository lookup**: Since public repository discovery/search is not
  exposed in the public sr.ht API, add a manual `~owner/repo` lookup flow that
  can open git.sr.ht or hg.sr.ht repositories directly.

- **paste.sr.ht tab**: Paste support. Endpoint:
  https://paste.sr.ht/graphql. Show the authenticated user's pastes, allow
  viewing individual pastes, and support creating new pastes. Required scope:
  PASTES:RO for browsing, PASTES:RW for creation/editing.

- **lists.sr.ht tab**: Mailing list support. Endpoint:
  https://lists.sr.ht/graphql. Show the authenticated user's mailing lists,
  allow browsing email threads, and display individual emails as plain text.
  Required scope: LISTS:RO.

- **pages.sr.ht tab**: Site management support. Endpoint:
  https://pages.sr.ht/graphql. Show the authenticated user's published sites,
  site metadata, publishing status, and access control where supported. This is
  for managing Pages sites, not browsing public project discovery.

- **Donation page / IAP**: Add a donation/support page once the App Store /
  StoreKit setup is ready.

## Out of Scope

- **Universal links** (e.g. tapping a git.sr.ht URL in Safari opens Hutch):
  Requires Sourcehut to host an apple-app-site-association file on their
  servers. This is outside our control. The hutch:// custom URL scheme works as
  a fallback for links we generate ourselves.

- **Push notifications for builds and tickets**: The sr.ht API only supports
  server-side webhooks (HTTP POST to a URL you control). Delivering push
  notifications to iOS would require a backend relay server to receive webhooks
  and forward them via APNs. Out of scope for a personal app with no backend.

- **Contribution activity / GitHub-style heatmap**: No aggregate contributions
  endpoint exists in the sr.ht GraphQL API. Computing this would require
  paginating every repository's full commit log and filtering by author --
  extremely slow and not practical.

- **Explore / search (hub.sr.ht)**: The public hub.sr.ht GraphQL API does not
  expose repository discovery/search or a projects feed comparable to
  https://sr.ht/projects.

- **Pronouns on profile**: Not exposed in the meta.sr.ht GraphQL schema. The
  field exists in the web UI but is not available to external API clients.

- **Revoke personal access tokens**: The revokePersonalAccessToken mutation is
  marked @internal in the meta.sr.ht schema and is not accessible to external
  clients.
