//
//  StorageDisclosureTests.swift
//  FridgeFitTests
//
//  What Settings tells the user about where their data is.
//
//  The row these replace said "Firestore account sync - Private, user-scoped
//  cloud storage", unconditionally, in a build whose pantry is a local
//  database. A claim about storage is only as good as its coupling to the
//  thing that decides storage, so these tests check the disclosure tracks
//  `PersistenceBackend` rather than being prose someone has to remember to
//  update.
//

import XCTest
@testable import FridgeFit

final class StorageDisclosureTests: XCTestCase {

    // MARK: - The shipping configuration

    /// `PersistenceConfiguration.compiledDefault` is `.swiftData`, so this is
    /// what a user actually reads.
    func test_swiftDataBackend_saysTheKitchenIsOnTheDeviceOnly() {
        let disclosures = StorageDisclosure.all(for: .swiftData)

        let kitchen = disclosures.first { $0.title.contains("Pantry") }
        XCTAssertEqual(kitchen?.location, .onDeviceOnly)

        let money = disclosures.first { $0.title.contains("Budget") }
        XCTAssertEqual(money?.location, .onDeviceOnly, "FridgeFunds now lives beside the pantry it values")
    }

    /// The bug this whole type exists for: in the shipping build nothing in
    /// the kitchen may be described as cloud storage.
    func test_swiftDataBackend_neverClaimsTheKitchenIsInTheCloud() {
        for disclosure in StorageDisclosure.all(for: .swiftData)
        where disclosure.title.contains("Pantry") || disclosure.title.contains("Budget") {
            XCTAssertEqual(disclosure.location, .onDeviceOnly)
            XCTAssertFalse(
                disclosure.detail.lowercased().contains("cloud"),
                "\"\(disclosure.title)\" describes local storage as cloud storage"
            )
        }
    }

    // MARK: - Firebase mode

    func test_firebaseBackend_saysTheKitchenIsInThePrivateCloud() {
        let disclosures = StorageDisclosure.all(for: .firebase)

        let kitchen = disclosures.first { $0.title.contains("Pantry") }
        XCTAssertEqual(kitchen?.location, .privateCloud)

        let money = disclosures.first { $0.title.contains("Budget") }
        XCTAssertEqual(money?.location, .privateCloud)
    }

    /// The two backends must actually differ, or the disclosure is not
    /// deriving anything and would survive the original bug.
    func test_theTwoBackendsProduceDifferentDisclosures() {
        XCTAssertNotEqual(
            StorageDisclosure.all(for: .swiftData),
            StorageDisclosure.all(for: .firebase),
            "The disclosure must depend on the backend, or it is just prose"
        )
    }

    // MARK: - Always true, whatever the backend

    /// Pairing and signalling are Firebase in every configuration, because
    /// two devices cannot rendezvous through a database only one of them can
    /// read. Describing them as local would be the mirror image of the
    /// original bug.
    func test_cameraPairingAndSignIn_areAlwaysCloud_inEveryBackend() {
        for backend in PersistenceBackend.allCases {
            let disclosures = StorageDisclosure.all(for: backend)

            let pairing = disclosures.first { $0.title.contains("Camera") }
            XCTAssertEqual(pairing?.location, .privateCloud, "\(backend): pairing is always Firebase")

            let signIn = disclosures.first { $0.title.contains("sign-in") }
            XCTAssertEqual(signIn?.location, .privateCloud, "\(backend): the account is always Firebase")
        }
    }

    /// Video and photos go peer-to-peer. The pairing row must say so, because
    /// "camera" plus "cloud" otherwise reads as uploaded video.
    func test_cameraPairingRow_saysVideoIsNotUploaded() {
        let pairing = StorageDisclosure.all(for: .swiftData).first { $0.title.contains("Camera") }
        let detail = try? XCTUnwrap(pairing?.detail)
        XCTAssertTrue(
            (detail ?? "").lowercased().contains("never uploaded"),
            "The pairing row must make clear that video is not uploaded, got: \(detail ?? "nil")"
        )
    }

    /// Every backend must produce a complete, well-formed set - a missing or
    /// blank row is a silent omission in a privacy statement.
    func test_everyBackendProducesCompleteWellFormedDisclosures() {
        for backend in PersistenceBackend.allCases {
            let disclosures = StorageDisclosure.all(for: backend, onlineRecipesEnabled: true)

            XCTAssertEqual(
                disclosures.count, 5,
                "\(backend) should disclose all five data kinds when online search is on"
            )
            XCTAssertEqual(
                Set(disclosures.map(\.id)).count,
                disclosures.count,
                "\(backend) has duplicate rows, which would break the ForEach id"
            )

            for disclosure in disclosures {
                XCTAssertFalse(disclosure.title.isEmpty, "\(backend) has an untitled row")
                XCTAssertFalse(disclosure.detail.isEmpty, "\(backend): \"\(disclosure.title)\" has no detail")
                XCTAssertFalse(disclosure.location.shortLabel.isEmpty)
            }
        }
    }

    // MARK: - The third party

    /// The one transfer to a company that is not FridgeFit. Settings is
    /// headed "where your data lives"; omitting this row was an inaccuracy
    /// by omission, because the search carries the user's Avoid list, which
    /// is user-provided health information.
    func test_whenOnlineSearchIsOn_theThirdPartyTransferIsDisclosed() {
        let disclosures = StorageDisclosure.all(for: .swiftData, onlineRecipesEnabled: true)
        let search = disclosures.first { $0.title.contains("Discover") }

        let row = try? XCTUnwrap(search)
        XCTAssertNotNil(row, "the Spoonacular transfer is not disclosed")
        XCTAssertEqual(row?.location, .thirdParty(name: "Spoonacular"))

        let detail = (row?.detail ?? "").lowercased()
        XCTAssertTrue(detail.contains("avoid list"), "the Avoid list must be named, got: \(detail)")
        XCTAssertTrue(detail.contains("isn't linked to you") || detail.contains("not linked"))
    }

    /// With the provider off, Discover performs no networking at all, so a
    /// row describing a transfer would be describing something that cannot
    /// happen.
    func test_whenOnlineSearchIsOff_noTransferIsClaimed() {
        let disclosures = StorageDisclosure.all(for: .swiftData, onlineRecipesEnabled: false)

        XCTAssertNil(disclosures.first { $0.title.contains("Discover") })
        XCTAssertFalse(disclosures.contains { $0.location == .thirdParty(name: "Spoonacular") })
    }

    /// The third-party row must be visually and textually distinct from the
    /// private-cloud rows: "stored under your account, readable by nobody
    /// else" and "handed to another company" are different promises.
    func test_theThirdPartyLabelIsDistinctFromPrivateCloud() {
        XCTAssertNotEqual(
            DataLocation.thirdParty(name: "Spoonacular").shortLabel,
            DataLocation.privateCloud.shortLabel
        )
        XCTAssertTrue(
            DataLocation.thirdParty(name: "Spoonacular").shortLabel.contains("Spoonacular"),
            "the recipient must be named"
        )
    }

    /// The live default must match the feature switch, or Settings would
    /// describe a configuration the app is not in.
    func test_theDefaultTracksTheLiveFeatureState() {
        let live = StorageDisclosure.all(for: .swiftData)
        let expected = StorageDisclosure.all(
            for: .swiftData,
            onlineRecipesEnabled: OnlineRecipeFeature.provider == .enabled
        )
        XCTAssertEqual(live, expected)
    }

    // MARK: - The sync claim

    /// FridgeFit has no iCloud, no CloudKit and no cross-device sync. Saying
    /// so explicitly is the difference between "we didn't claim sync" and
    /// "we told the user there isn't any".
    func test_theNoSyncNotice_saysSoExplicitly() {
        let notice = StorageDisclosure.noSyncNotice.lowercased()
        XCTAssertTrue(notice.contains("icloud"), "The notice must name iCloud, which users expect")
        XCTAssertTrue(notice.contains("doesn't sync") || notice.contains("does not sync"))
    }

    /// No row, in any backend, may claim iCloud or cross-device sync.
    ///
    /// The check is deliberately for an *affirmative* claim. A naive search
    /// for "synced between" fails the on-device row, whose detail reads
    /// "Not uploaded, and not synced between devices" - which is the
    /// statement this test wants to see, not the one it wants to catch. So
    /// negated mentions are stripped before looking.
    func test_noDisclosureClaimsICloudOrCrossDeviceSync() {
        let negations = ["not synced", "doesn't sync", "does not sync", "not uploaded", "never uploaded"]

        for backend in PersistenceBackend.allCases {
            for disclosure in StorageDisclosure.all(for: backend) {
                var text = (disclosure.title + " " + disclosure.detail).lowercased()
                for negation in negations {
                    text = text.replacingOccurrences(of: negation, with: "")
                }

                XCTAssertFalse(text.contains("icloud"), "\(backend): \"\(disclosure.title)\" claims iCloud")
                for claim in ["synced between", "syncs between", "sync your", "synced to"] {
                    XCTAssertFalse(
                        text.contains(claim),
                        "\(backend): \"\(disclosure.title)\" claims cross-device sync (\"\(claim)\")"
                    )
                }
            }
        }
    }

    /// The counterpart: the on-device row must actively say it is not synced,
    /// rather than merely avoiding the word.
    func test_theOnDeviceRow_activelyDeniesSync() {
        let kitchen = StorageDisclosure.all(for: .swiftData).first { $0.title.contains("Pantry") }
        let detail = (kitchen?.detail ?? "").lowercased()
        XCTAssertTrue(
            detail.contains("not synced") || detail.contains("not uploaded"),
            "The on-device row should say what does not happen, got: \(detail)"
        )
    }

    /// The on-device label must not be mistakable for cloud storage.
    func test_locationLabelsAreUnambiguous() {
        XCTAssertFalse(DataLocation.onDeviceOnly.shortLabel.lowercased().contains("cloud"))
        XCTAssertTrue(DataLocation.privateCloud.shortLabel.lowercased().contains("cloud"))
        XCTAssertNotEqual(DataLocation.onDeviceOnly.shortLabel, DataLocation.privateCloud.shortLabel)
    }
}
