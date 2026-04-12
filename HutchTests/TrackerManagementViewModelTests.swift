import Testing
@testable import Hutch

struct TrackerManagementViewModelTests {

    @Test
    @MainActor
    func normalizedUsernameStripsLeadingTildeAndWhitespace() {
        #expect(TrackerManagementViewModel.normalizedUsername("  ~alice  ") == "alice")
        #expect(TrackerManagementViewModel.normalizedUsername("bob") == "bob")
    }

    @Test
    @MainActor
    func hexColorValidationRequiresPoundAndSixHexDigits() {
        #expect(TrackerManagementViewModel.isValidHexColor("#a1B2c3"))
        #expect(!TrackerManagementViewModel.isValidHexColor("a1B2c3"))
        #expect(!TrackerManagementViewModel.isValidHexColor("#12345"))
        #expect(!TrackerManagementViewModel.isValidHexColor("#12GG45"))
    }

    @Test
    func trackerACLPermissionsExposeBooleanFlags() {
        let permissions = TrackerACLPermissions(
            browse: true,
            submit: false,
            comment: true,
            edit: false,
            triage: true
        )

        #expect(permissions.browse)
        #expect(!permissions.submit)
        #expect(permissions.comment)
        #expect(!permissions.edit)
        #expect(permissions.triage)
    }
}
