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

## Phase 1: Close the write gaps — done (v3.6.0)

Small, independently shippable mutations that already existed in the API but
were never called. Each removes a "why can't I do this here?" moment.

- ~~`updateTicket`~~ — edit a ticket's subject and body after creation.
- ~~`deleteTicket`~~ — delete a ticket, behind a confirmation.
- ~~`ticketSubscribe` / `ticketUnsubscribe`, `trackerSubscribe` /
  `trackerUnsubscribe`~~ — `Ticket.subscription` and `Tracker.subscription` are
  null when not subscribed, so both toggles reflect real server state.
- ~~`mailingListUnsubscribe`~~ — see the caveat below.
- ~~`updatePreferences`~~ (todo.sr.ht and lists.sr.ht) — `notifySelf` and
  `copySelf`, surfaced as an Email section in Settings.

`mailingListSubscribe` is deliberately not wired up. `MailingList` has no
`subscription` field, unlike `Ticket` and `Tracker`, so per-list state is only
knowable from the `subscriptions` query — which by definition lists what the
user is already subscribed to. Subscribing needs a list the user is *not*
subscribed to, and sr.ht exposes no discovery API to find one (see
[SCOPE.md](SCOPE.md) on hub.sr.ht). Revisit if hub.sr.ht ever gains an API, or
alongside Phase 2, which surfaces lists through patchsets.

### Refactors folded in

- ~~Collapse `SRHTClient`'s duplicated request paths~~. Extracted
  `makeAuthorizedRequest`, `send`, and `encodedGraphQLBody`; `executeMultipart`
  became the single-file case of `executeMultipartFiles`. The `#if DEBUG`
  logging block went from five copies to one. 938 lines to 569.
- ~~Unify the two `executeCached` overloads~~. The memory-only overload and
  `executeAndCache` turned out to be dead — all 38 call sites already used the
  TTL-aware path — so both were removed rather than merged. `responseCache`
  remains as the in-memory layer behind `cachedPayload`.

Known follow-up: `BuildListViewModel`, `RepositoryListViewModel`, and
`PasteService` still read `client.responseCache` directly, falling back across
two different cache keys. That predates `APICacheKeys` and should be folded into
`cachedPayload`.

## Phase 2: Patchsets — done (v3.7.0)

The flagship gap. Sending and reviewing patches over email is the SourceHut
contribution model, and Hutch had no reference to `patchset` anywhere.

Scoped as review-and-triage, not submission:

- ~~Patchset list per mailing list~~ — see the caveat below.
- ~~Patchset detail~~: cover letter, per-patch diffs (via the existing
  `DiffView`), checks, and the version / superseded-by chain.
- ~~Status transitions via `updatePatchset`~~.

Two schema facts shaped the result, and are worth knowing before extending this:

- **`MailingList` has no `patchsets` field.** A list's patchsets cannot be
  queried directly; they are reachable only through thread roots. The existing
  threads query now also selects `root.patchset`, so the Patches tab costs no
  extra request — but it also means patchsets cannot be filtered by status
  server-side, and only patchsets whose thread appears in the current page are
  listed.
- **`Patch` carries no diff.** It has only `index`, `count`, `version`,
  `prefix`, `subject`, and `trailers`. The diff exists solely inside the email
  body, so it is recovered with `InboxThreadUtilities.segmentMessageBody` — the
  same splitter the inbox thread view uses.

Patch *submission* remains out of reach: it is a `git send-email` flow, not a
GraphQL mutation. Treat that boundary as explicit rather than half-building it.

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
