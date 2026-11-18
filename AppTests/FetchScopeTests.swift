import CloudKit
import Testing
@testable import FeedingDev

/// Every sync engine fetch leaves out the photos zone and keeps the household zone (eng D8, OE1a
/// and eng D6 part 1, 18 Nov 2026). A push-woken fetch has seconds, and the alarms wait on it.
/// The automatic and push fetches use the role; the join fetch uses the owner's name from the
/// invite, as the role isn't known yet; a photos zone the database reported stays out even if the
/// role is lost (Codex review of step 0).
@MainActor
@Suite("What a fetch leaves out")
struct FetchScopeTests {
    let owner = "_3f1c0ownerRecordName"

    func zone(_ name: String, _ ownerName: String) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: name, ownerName: ownerName)
    }

    func scope(_ database: CKDatabase.Scope, _ role: HouseholdSync.Role, joining: String? = nil,
               known: Set<String> = []) -> CKSyncEngine.FetchChangesOptions.Scope {
        HouseholdSync.restricted(.all, leavingOut: HouseholdSync.photosZoneIDs(for: database, role: role,
                                                                               joiningOwner: joining, knownOwners: known))
    }

    @Test func theOwnersFetchesLeaveOutTheirPhotosZone() {
        let scope = scope(.private, .owner)
        #expect(!scope.contains(zone(AppConfig.photosZoneName, CKCurrentUserDefaultName)))
        #expect(scope.contains(zone(HouseholdSync.zoneName, CKCurrentUserDefaultName)))
    }

    @Test func aMembersFetchesLeaveOutTheOwnersPhotosZone() {
        let scope = scope(.shared, .member(ownerName: owner))
        #expect(!scope.contains(zone(AppConfig.photosZoneName, owner)))
        #expect(scope.contains(zone(HouseholdSync.zoneName, owner)))
    }

    @Test func joiningLeavesOutThePhotosZoneNamedInTheInvite() {
        let scope = scope(.shared, .notSetUp, joining: owner)
        #expect(!scope.contains(zone(AppConfig.photosZoneName, owner)))
        #expect(scope.contains(zone(HouseholdSync.zoneName, owner)))
    }

    @Test func aPhotosZoneAlreadySeenStaysOutWhenTheRoleIsLost() {
        let scope = scope(.shared, .notSetUp, known: [owner])
        #expect(!scope.contains(zone(AppConfig.photosZoneName, owner)))
        #expect(scope.contains(zone(HouseholdSync.zoneName, owner)))
    }

    @Test func everyRoleStillFetchesTheHouseholdZone() {
        for role: HouseholdSync.Role in [.notSetUp, .owner, .member(ownerName: owner)] {
            #expect(scope(.private, role, known: [owner]).contains(zone(HouseholdSync.zoneName, CKCurrentUserDefaultName)))
            #expect(scope(.shared, role, joining: owner, known: [owner]).contains(zone(HouseholdSync.zoneName, owner)))
        }
    }

    /// The engine asks again before each fetch, with the options the fetch was started with. Those
    /// keep their own limits, and the photos zone is always added to what is left out.
    @Test func anExplicitFetchKeepsItsOwnLimits() {
        let photos = [zone(AppConfig.photosZoneName, owner)]
        let other = zone("Other", owner)
        let household = zone(HouseholdSync.zoneName, owner)
        let excluding = HouseholdSync.restricted(.allExcluding([other]), leavingOut: photos)
        #expect(!excluding.contains(other))
        #expect(!excluding.contains(photos[0]))
        #expect(excluding.contains(household))
        let only = HouseholdSync.restricted(.zoneIDs([household, photos[0]]), leavingOut: photos)
        #expect(only.contains(household))
        #expect(!only.contains(photos[0]))
        #expect(!only.contains(other))
    }

    @Test func thePhotosZoneIsNotTheHouseholdZone() {
        #expect(AppConfig.photosZoneName != HouseholdSync.zoneName)
    }
}
