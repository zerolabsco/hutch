# Roadmap

Planned work for Hutch, ordered by dependency. Feature gaps below were
identified by diffing the GraphQL schema dumps in `Docs/API` against actual
call sites in the Swift source.

See [SCOPE.md](SCOPE.md) for features that are intentionally out of scope.

## SourceHut API traps

Things the schema does not tell you, each of which has already cost real time.

- **`Thread.updated` is not the thread's activity.** It is the root email's
  insert time and never advances when a reply arrives, despite the name and
  despite the schema describing `MailingList.threads` as ordered "most recently
  bumped". sr.ht returns `updated` seven seconds after `root.date` on a thread
  carrying four replies. Anything built on it silently treats thread creation as
  activity. Use `MailingList.emails`, which is reverse-chronological arrival
  data — see `MailingListActivity`. Prefer `Email.received` over `Email.date`:
  `received` is server-side and non-null, `date` comes from the sender's header
  and is neither.
- **The schema dumps in `Docs/API` are partial.** They were captured with an
  introspection query that omits `inputFields` and `enumValues`, so they cannot
  answer what a mutation's input looks like or what an enum accepts — both come
  back as empty arrays rather than as an error. For input shapes and enum cases,
  read the real SDL instead:
  `git clone --depth 1 https://git.sr.ht/~sircmpwn/<service>.sr.ht` and look at
  `api/graph/schema.graphqls`. Regenerating the dumps with a full introspection
  query would remove the trap.

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
- Three were real bugs the suite had been right about all along: repository
  descriptions could not be cleared (a nil subscript assignment drops the key
  instead of sending JSON null), `serviceNotProvisioned` was unreachable behind
  a broader `no such` match, and code spans rendered their contents as live
  markup.
- One was neither. `keepsDistinctThreadsDistinctByRootMessageID` asserted that
  two same-subject threads get distinct `id`s, and `eff81f3` obliged by keying
  `id` on the root Message-ID. The commit message claims this fixed an
  `Identifiable` collision; it did not, because `deduplicateThreads` merges
  same-subject threads into one summary before anything renders, so the
  collision is unreachable. The test constructed summaries by hand and skipped
  that step. The change is harmless and separating identity from grouping reads
  better, but the stated reason was wrong.

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

Known follow-up: three view models still read `client.responseCache` directly.
Tracked under Phase 3.

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

Unlike Phases 1 and 2, this is not one shippable thing. It is several, and they
are sized very differently — measure before committing to one.

### API features — done (v3.8.0)

- ~~`uploadArtifact` / `deleteArtifact`~~ — artifacts were read-only.
- ~~`auditLog` (meta.sr.ht)~~ — surfaced under the tokens in Profile.
- ~~Mailing list creation and settings~~ (`createMailingList`,
  `updateMailingList`, `deleteMailingList`).

Three of the six planned. The other three did not survive contact:

- `archiveMessage` is `@internal` and inaccessible.
- The `events` feed was built, then removed: todo.sr.ht's root `events` resolver
  joins `event.participant_id` against `participant.user_id`, which are
  different id spaces, so it returns an empty list for everyone. See
  [SCOPE.md](SCOPE.md).
- Webhook management, `shareSecret`, and build groups are reachable but declined
  on judgement — see [SCOPE.md](SCOPE.md) for the reasoning, so they do not get
  re-proposed.

### Localization

The project sets `LOCALIZATION_PREFERS_STRING_CATALOGS = YES` but ships no
string catalog, so every user-facing string is hardcoded English. Roughly 634
literals: 239 `Text(`, 150 `Label(`, 117 `Button(`, 77 `Section(`, 51
`navigationTitle(`.

Worth knowing before starting: a catalog containing only English changes nothing
for users until translations exist. It is groundwork, and it is the largest diff
in the roadmap — it touches nearly every view, with the regression risk that
implies.

### Accessibility

Labels and hints appear in 17 of 89 view files. Mechanical and low-risk, but it
cannot be verified from a build — it needs VoiceOver driven on a device.

### Swift 6 language mode

The project builds in Swift 5 language mode with
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Moving to Swift 6 is blocked on
concurrency diagnostics that are warnings today and errors there:

- `APICacheTests` and `BundleUserAgentTests` call main-actor-isolated
  initialisers and properties from nonisolated contexts, and `await` a few
  expressions without marking them. Roughly 20 warnings, all in tests.
- Response types are implicitly `@MainActor` under the default isolation, so
  their `Decodable` conformances are too. Decoding one from a nonisolated
  context — an `async let` over a raw `client.execute`, say — warns now and
  fails then. The pattern that avoids it is `async let` over `@MainActor`
  methods, as in `HomeViewModel.loadDashboard` and
  `NotificationPreferencesViewModel.load`.

### Cache reads that bypass the client

`BuildListViewModel`, `RepositoryListViewModel`, and `PasteService` still read
`client.responseCache` directly, each falling back across two different cache
keys. That predates `APICacheKeys` and should be folded into `cachedPayload`,
which already consults the persistent cache before the memory layer.

## Housekeeping

- `Hutch/Hutch/App/AccountSession.swift` sits in a stray nested directory;
  `Hutch/HutchTests/` is empty.
