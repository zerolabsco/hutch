# SourceHut API Cache

Hutch caches read-only SourceHut API responses at the `SRHTClient` boundary. The cache stores raw response bytes plus metadata on disk, with a small bounded memory layer for hot entries. Disk files are account-scoped under the app caches directory, and `PersistentAPICache` is an actor so disk I/O, pruning, and metadata updates stay off the main actor.

Cache keys are built in `APICacheKeys`. Keys are explicit and include the service plus request-shaping inputs such as repository IDs, refs, tree/blob IDs, paths, owners, ticket IDs, job IDs, log URLs, cursors, and filters. Views and view models should not invent ad hoc cache strings.

TTLs live in `APICacheTTLs`. Active build data uses a very short TTL, mutable ticket and list data use medium-short TTLs, repository metadata and profile data live longer, completed build logs are long-lived, and content-addressed git objects are treated as mostly immutable. Moving refs such as `HEAD` use shorter file/content TTLs.

Invalidation is intentionally prefix-based. Successful ticket mutations remove ticket, ticket-list, tracker, and Home prefixes. Build retry/cancel/resubmit actions remove build detail, build-list, build-log, and Home prefixes. This avoids a dependency graph while keeping stale post-mutation data out of the high-risk paths.

Known limitations: caching now covers the high-value detail paths plus repository/build/ticket/tracker/paste lists, profile repositories/trackers, projects, and Home dashboard fetches. Some services still perform background refresh one request at a time rather than streaming partial refreshed list pages into the UI, and Work Queue-specific surfaces should be reviewed as a follow-up if they grow beyond the Home dashboard data model.
