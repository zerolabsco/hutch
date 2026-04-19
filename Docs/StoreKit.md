# StoreKit Setup For Hutch

Hutch uses StoreKit 2 for one-time consumable tip products:

- `net.cleberg.hutch.tip.small`
- `net.cleberg.hutch.tip.medium`
- `net.cleberg.hutch.tip.large`

## Xcode setup

1. Open `Hutch.xcodeproj` in Xcode.
2. Select the `Hutch` target.
3. Open `Signing & Capabilities`.
4. Confirm the App ID for `net.cleberg.Hutch` has the In-App Purchase capability enabled in the Apple Developer portal.
5. In Xcode, choose `File > New > File... > StoreKit Configuration File`.
6. Prefer a synced StoreKit file so Xcode pulls the real products from App Store Connect.
7. Open `Product > Scheme > Edit Scheme...`.
8. Select `Run`, then the `Options` tab.
9. Set `StoreKit Configuration` to the synced `.storekit` file for local testing.

## App Store Connect checks

1. Confirm all three products exist with the exact product IDs listed above.
2. Confirm each product has complete metadata, pricing, and availability.
3. If a product is in `Developer Action Needed`, edit the rejected detail or cancel the pending change, then resubmit it.
4. Wait up to one hour for metadata changes to propagate to sandbox.

## Sandbox test checklist

1. On a physical device, enable Developer Mode if needed.
2. Sign in to a Sandbox Apple Account in `Settings > Developer > Sandbox Apple Account`.
3. Install a development build from Xcode or a TestFlight build.
4. Open `More > About`.
5. Verify the tip products load with names and prices.
6. Complete one purchase successfully.
7. Use `Restore / Sync Purchases` to verify StoreKit can talk to the App Store account.
8. Record this full flow for App Review when resubmitting.

## Code locations

- `Hutch/Views/More/TipStoreViewModel.swift`
- `Hutch/Views/More/AboutView.swift`
