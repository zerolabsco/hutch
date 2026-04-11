# Hutch
iOS client for SourceHut.

[![builds.sr.ht status](https://builds.sr.ht/~ccleberg/Hutch.svg)](https://builds.sr.ht/~ccleberg/Hutch?)
[![Security Rating](https://sonarcloud.io/api/project_badges/measure?project=zerolabsco_hutch&metric=security_rating)](https://sonarcloud.io/summary/new_code?id=zerolabsco_hutch)
[![Reliability Rating](https://sonarcloud.io/api/project_badges/measure?project=zerolabsco_hutch&metric=reliability_rating)](https://sonarcloud.io/summary/new_code?id=zerolabsco_hutch)

## Overview

Hutch is a native SwiftUI app for browsing and managing SourceHut services on iPhone and iPad. It uses SourceHut's GraphQL APIs and stores your personal access token in the iOS keychain.

The app currently includes:

- Home dashboard with assigned tickets, recent builds, and projects
- Repository browsing for Git and Mercurial repositories
- Repository details including README, references, commits, diffs, files, artifacts, and settings
- Tracker and ticket browsing, ticket detail views, and tracker creation
- Build job browsing, build detail views, and build submission
- Inbox and mailing list reading flows
- Paste browsing, creation, and detail views
- Profile and account settings, including SSH keys, PGP keys, and personal access token management
- Deep links for repositories, tickets, and build jobs

Some SourceHut services are still browser-only from within Hutch. Unsupported areas currently open in Safari instead of rendering in-app.

## Requirements

- Xcode with current iOS SDK support
- iOS Simulator or physical iOS device
- A SourceHut account
- A SourceHut personal access token

## Getting Started

1. Clone the repository:

   ```sh
   git clone https://git.sr.ht/~ccleberg/Hutch
   ```

2. Open the project in Xcode.
3. Build and run the app on a simulator or device.
4. On first launch, create or paste a SourceHut personal access token.

You can create a token at:

- `https://meta.sr.ht/oauth/personal-access-tokens`

## Using Hutch

After signing in with a valid token, Hutch presents five primary areas:

- `Home`: dashboard for projects, assigned tickets, recent builds, and inbox access
- `Repositories`: browse, search, create, and manage repositories
- `Tickets`: browse trackers, create trackers, and view ticket details
- `Builds`: inspect build jobs and submit new builds
- `More`: lists, pastes, settings, and external links for unsupported services

Authentication notes:

- Hutch validates the token against `meta.sr.ht` before saving it
- The token is stored in the iOS keychain
- `Reset App Data` removes saved token data, caches, cookies, and local web data from the device

## Development

The project is an Xcode app with tests under `HutchTests`.

Typical workflow:

1. Open the workspace or project in Xcode.
2. Select the Hutch app scheme.
3. Build the app.
4. Run the test plan in `Hutch/HutchTests.xctestplan`.

## Contributing

Contributions are welcome. Keep changes scoped, include tests when behavior changes, and open a pull request with a clear summary of the user-facing impact.

## Security

If you discover a security issue, see [SECURITY.md](SECURITY.md).

## License

This project is licensed under the GPL 3.0 or later. See [LICENSE](LICENSE).

## Contact

Questions or feedback: hello@cleberg.net
