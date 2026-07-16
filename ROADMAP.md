# Roadmap

Planned work for Hutch, ordered by dependency. Feature gaps below were
identified by diffing the GraphQL schema dumps in `Docs/API` against actual
call sites in the Swift source.

See [SCOPE.md](SCOPE.md) for features that are intentionally out of scope.

## Phase 0: Unblock CI — done (v3.5.0)

Nothing downstream is trustworthy until the build badge means something.

- ~~Fix `repo-structure-check` in `builds/swift-ci.yml`~~. It asserted
  `test -d "website"`, but `website/` was removed in `24c8bc6` (2026-04-10), so
  the check had failed since then.
- ~~Add a macOS CI job that runs `xcodebuild test`~~. builds.sr.ht has no macOS
  image and its maintainer has ruled them out, so `xcodebuild` cannot run there.
  The test plan now runs on the GitHub mirror via `.github/workflows/test.yml`;
  builds.sr.ht keeps secret scanning and structure checks.

Turning the gate on first required making the suite green. All 214 tests had
been running only on demand in Xcode, and ten had rotted:

- The `Hutch` scheme referenced `container:HutchTests` without the
  `.xctestplan` extension, so `xcodebuild test -scheme Hutch` — the path the
  README sends contributors down — could not run at all.
- Five were test-side rot: uppercase GraphQL enum rawValues asserted as
  lowercase, an ordering expectation predating `sortBuildItemsForTriage`,
  `request.httpBody` read inside a `URLProtocol` (always nil; the body lives on
  `httpBodyStream`), an incident fixture contradicting its own RSS input, and an
  image assertion that treated the correct `&amp;` attribute encoding as a bug.
- Four were real bugs the suite had been right about all along: repository
  descriptions could not be cleared (a nil subscript assignment drops the key
  instead of sending JSON null), `serviceNotProvisioned` was unreachable behind
  a broader `no such` match, code spans rendered their contents as live markup,
  and inbox threads keyed `id` on a subject-derived grouping key so two threads
  sharing a subject on one list collided under `Identifiable`.

## Phase 1: Close the write gaps

Small, independently shippable mutations that already exist in the API but are
never called. Each removes a "why can't I do this here?" moment.

- `updateTicket` — edit ticket title and description after creation. Currently
  a ticket can be created and its status changed, but never edited.
- `deleteTicket` — delete a ticket.
- `trackerSubscribe` / `trackerUnsubscribe`, `ticketSubscribe` /
  `ticketUnsubscribe`, `mailingListSubscribe` / `mailingListUnsubscribe` —
  subscriptions are currently read-only. `MailingListListView` reads the
  `subscriptions` query, but nothing can subscribe or unsubscribe.
- `updatePreferences` (todo.sr.ht and lists.sr.ht) — email notification
  preferences.

### Refactors to fold in

These are touched by everything in later phases, so they belong here rather
than as standalone work.

- `SRHTClient` has four near-identical request-and-decode paths (`execute`,
  `executeMultipart`, `executeMultipartFiles`, `executeAndCache`, plus the
  private `performGraphQLRequest`). The token guard, header setup, status-code
  handling, and a ~35-line `#if DEBUG` logging block are each duplicated about
  five times. Collapse to one request builder and one decode helper.
- Two caches overlap: the in-memory `responseCache` and the persistent `cache`,
  reached through two different `executeCached` overloads with different return
  types and semantics (one does stale-while-revalidate with TTLs, the other only
  checks memory). Unify on the TTL-aware path.

## Phase 2: Patchsets

The flagship gap. There is currently no reference to `patchset` anywhere in the
Swift source, yet lists.sr.ht exposes a full `Patchset` type (subject, version,
prefix, status, coverLetter, patches, tools, mbox), a `patchset` query, and an
`updatePatchset` mutation. Sending and reviewing patches over email is the
SourceHut contribution model, and Hutch cannot currently participate in it.

Scope this as review-and-triage, not submission:

- Patchset list per mailing list.
- Patchset detail: cover letter, per-patch diffs (reuse the existing
  `DiffView`), version and superseded-by chain.
- Status transitions via `updatePatchset`.

Patch *submission* is an email / `git send-email` flow and is likely out of
reach from the app. Treat that boundary as explicit rather than half-building
it.

## Phase 3: Polish and reach

- **Localization.** The project sets `LOCALIZATION_PREFERS_STRING_CATALOGS =
  YES` but ships no string catalog, so every user-facing string is hardcoded
  English.
- **Accessibility.** Labels and hints appear in only 16 of roughly 130 view
  files.
- `uploadArtifact` / `deleteArtifact` — artifacts are read-only today.
- Webhook management. Zero calls to any `create*Webhook` across every service.
  Push notifications are out of scope because they need a relay server (see
  [SCOPE.md](SCOPE.md)), but webhook management is client-side only and is a
  prerequisite if that relay ever ships.
- `auditLog` (meta.sr.ht) — unused security surface.
- Build groups (`createGroup`, `startGroup`) and secret management
  (`shareSecret`, the `secrets` query). Today `secrets` is only a submit toggle.
- Mailing list creation and settings (`createMailingList`, `updateMailingList`,
  `deleteMailingList`).
- `events` feed (todo.sr.ht) and `archiveMessage` (lists.sr.ht).

## Housekeeping

- `Hutch/Hutch/App/AccountSession.swift` sits in a stray nested directory;
  `Hutch/HutchTests/` is empty.
</content>
</invoke>
