import Foundation
import Testing
@testable import Hutch

struct PatchsetStatusTests {

    @Test
    func statusRawValuesMatchTheGraphQLEnum() {
        // lists.sr.ht's PatchsetStatus enum values, which are sent verbatim to
        // updatePatchset.
        #expect(PatchsetStatus.unknown.rawValue == "UNKNOWN")
        #expect(PatchsetStatus.proposed.rawValue == "PROPOSED")
        #expect(PatchsetStatus.needsRevision.rawValue == "NEEDS_REVISION")
        #expect(PatchsetStatus.superseded.rawValue == "SUPERSEDED")
        #expect(PatchsetStatus.approved.rawValue == "APPROVED")
        #expect(PatchsetStatus.rejected.rawValue == "REJECTED")
        #expect(PatchsetStatus.applied.rawValue == "APPLIED")
    }

    @Test
    func assignableStatusesExcludeServerManagedOnes() {
        // UNKNOWN is a sentinel and SUPERSEDED is set by the server when a newer
        // version lands, so neither should be offered as a reviewer choice.
        #expect(!PatchsetStatus.assignable.contains(.unknown))
        #expect(!PatchsetStatus.assignable.contains(.superseded))
        #expect(PatchsetStatus.assignable.contains(.approved))
        #expect(PatchsetStatus.assignable.contains(.rejected))
        #expect(PatchsetStatus.assignable.contains(.applied))
        #expect(PatchsetStatus.assignable.contains(.needsRevision))
        #expect(PatchsetStatus.assignable.contains(.proposed))
    }

    @Test
    func openStatusesAreThoseAwaitingADecision() {
        #expect(PatchsetStatus.proposed.isOpen)
        #expect(PatchsetStatus.needsRevision.isOpen)
        #expect(!PatchsetStatus.applied.isOpen)
        #expect(!PatchsetStatus.rejected.isOpen)
        #expect(!PatchsetStatus.superseded.isOpen)
    }

    @Test
    func statusDecodesFromTheWireFormat() throws {
        let decoded = try JSONDecoder().decode(PatchsetStatus.self, from: Data("\"NEEDS_REVISION\"".utf8))
        #expect(decoded == .needsRevision)
    }
}

struct PatchsetSummaryTests {

    @Test
    func versionLabelIsHiddenForFirstVersion() {
        let summary = PatchsetSummary(
            id: 1,
            subject: "[PATCH] fix the thing",
            version: 1,
            prefix: nil,
            status: .proposed
        )

        #expect(summary.versionLabel == nil)
    }

    @Test
    func versionLabelIsShownForRevisions() {
        let summary = PatchsetSummary(
            id: 1,
            subject: "[PATCH v3] fix the thing",
            version: 3,
            prefix: nil,
            status: .proposed
        )

        #expect(summary.versionLabel == "v3")
    }
}

@MainActor
struct PatchsetOrderingTests {

    private func makePatch(id: Int, index: Int?, count: Int?) -> PatchsetEmail {
        PatchsetEmail(
            id: id,
            subject: "patch \(id)",
            date: nil,
            sender: Entity(canonicalName: "~someone"),
            contentBlocks: [],
            index: index,
            count: count
        )
    }

    @Test
    func patchesAreOrderedBySeriesIndexNotReceiptOrder() {
        let patches = [
            makePatch(id: 30, index: 3, count: 3),
            makePatch(id: 10, index: 1, count: 3),
            makePatch(id: 20, index: 2, count: 3)
        ]

        let ordered = PatchsetDetailViewModel.orderPatches(patches)

        #expect(ordered.map(\.index) == [1, 2, 3])
    }

    @Test
    func unindexedPatchesAreKeptAtTheEndRatherThanDropped() {
        let patches = [
            makePatch(id: 99, index: nil, count: nil),
            makePatch(id: 20, index: 2, count: 2),
            makePatch(id: 10, index: 1, count: 2)
        ]

        let ordered = PatchsetDetailViewModel.orderPatches(patches)

        #expect(ordered.count == 3)
        #expect(ordered.map(\.index) == [1, 2, nil])
    }

    @Test
    func orderingIsStableForASingleUnindexedPatch() {
        // A lone patch with no [PATCH n/m] prefix is the common one-off case.
        let patches = [makePatch(id: 1, index: nil, count: nil)]

        let ordered = PatchsetDetailViewModel.orderPatches(patches)

        #expect(ordered.map(\.id) == [1])
    }

    @Test
    func seriesLabelIsHiddenForSinglePatchSeries() {
        let patch = makePatch(id: 1, index: 1, count: 1)
        #expect(patch.seriesLabel == nil)
    }

    @Test
    func seriesLabelShowsPositionForMultiPatchSeries() {
        let patch = makePatch(id: 1, index: 2, count: 5)
        #expect(patch.seriesLabel == "2/5")
    }
}
