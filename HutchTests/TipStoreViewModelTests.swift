import Foundation
import Testing
@testable import Hutch

struct TipStoreViewModelTests {

    @Test
    func tipProductIdentifiersMatchAppStoreConnectOrder() {
        #expect(TipStoreViewModel.productIDs == [
            "net.cleberg.hutch.tip.small",
            "net.cleberg.hutch.tip.medium",
            "net.cleberg.hutch.tip.large",
        ])
    }

    @Test
    func tipProductDisplayNamesMatchReviewMetadata() {
        #expect(TipStoreViewModel.TipProduct.small.displayName == "Small Tip")
        #expect(TipStoreViewModel.TipProduct.medium.displayName == "Medium Tip")
        #expect(TipStoreViewModel.TipProduct.large.displayName == "Large Tip")
    }
}
