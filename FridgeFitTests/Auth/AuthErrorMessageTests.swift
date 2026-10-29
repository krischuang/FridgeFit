//
//  AuthErrorMessageTests.swift
//  FridgeFitTests
//
//  What the sign-in screen says when something goes wrong.
//
//  Firebase's own `localizedDescription` used to go straight onto the
//  screen. These pin down the replacement, including the one case that is a
//  security property rather than a wording preference: a wrong email and a
//  wrong password must be indistinguishable.
//

import FirebaseAuth
import XCTest
@testable import FridgeFit

final class AuthErrorMessageTests: XCTestCase {

    private func authError(_ code: AuthErrorCode) -> NSError {
        NSError(domain: AuthErrorDomain, code: code.rawValue, userInfo: [
            NSLocalizedDescriptionKey: "Firebase's own wording, which must not reach the screen",
        ])
    }

    // MARK: - Account enumeration

    /// The important one. If "no such user" and "wrong password" differ,
    /// anyone can type an email into the sign-in form and learn whether it is
    /// registered. `sendPasswordReset` already refuses to reveal this; the
    /// sign-in path now matches it.
    func test_wrongPasswordAndUnknownUser_areIndistinguishable() {
        let wrongPassword = AuthErrorMessage.text(for: authError(.wrongPassword))
        let noSuchUser = AuthErrorMessage.text(for: authError(.userNotFound))
        let badCredential = AuthErrorMessage.text(for: authError(.invalidCredential))

        XCTAssertEqual(wrongPassword, noSuchUser, "These must not be distinguishable")
        XCTAssertEqual(wrongPassword, badCredential)
        XCTAssertFalse(wrongPassword.isEmpty)
    }

    // MARK: - Actionable wording

    func test_eachMappedCode_hasItsOwnActionableMessage() {
        let cases: [(AuthErrorCode, String)] = [
            (.invalidEmail, "valid email"),
            (.userDisabled, "disabled"),
            (.emailAlreadyInUse, "already exists"),
            (.weakPassword, "too easy to guess"),
            (.networkError, "connection"),
            (.tooManyRequests, "Too many attempts"),
            (.accountExistsWithDifferentCredential, "different sign-in method"),
        ]

        for (code, expectedFragment) in cases {
            let message = AuthErrorMessage.text(for: authError(code))
            XCTAssertTrue(
                message.contains(expectedFragment),
                "\(code) produced \"\(message)\", which doesn't mention \"\(expectedFragment)\""
            )
        }
    }

    /// Firebase's own text must never reach the screen, for any code - known
    /// or not.
    func test_firebasesOwnWording_neverReachesTheScreen() {
        let codes: [AuthErrorCode] = [
            .wrongPassword, .userNotFound, .invalidEmail, .userDisabled,
            .emailAlreadyInUse, .weakPassword, .networkError, .tooManyRequests,
            .accountExistsWithDifferentCredential, .credentialAlreadyInUse,
            .requiresRecentLogin, .invalidCredential,
        ]

        for code in codes {
            let message = AuthErrorMessage.text(for: authError(code))
            XCTAssertFalse(
                message.contains("Firebase's own wording"),
                "\(code) leaked the underlying description"
            )
            for leak in ["Firebase", "FIRAuth", "ERROR_", "NSError", "Optional"] {
                XCTAssertFalse(message.contains(leak), "\(code) leaked \"\(leak)\": \(message)")
            }
        }
    }

    /// An unrecognised code must fall back to FridgeFit's generic retry, not
    /// to the underlying message - an unknown code is exactly where the
    /// underlying text is least likely to be suitable.
    func test_anUnknownCode_fallsBackToAGenericRetry_notTheUnderlyingText() {
        let unknown = NSError(domain: AuthErrorDomain, code: 999_999, userInfo: [
            NSLocalizedDescriptionKey: "FIRAuthInternalErrorDomain exploded",
        ])

        let message = AuthErrorMessage.text(for: unknown)

        XCTAssertFalse(message.isEmpty)
        XCTAssertFalse(message.contains("exploded"))
        XCTAssertTrue(message.contains("try again"))
    }

    /// Backing out of Google's sheet is the user's own decision. Showing a
    /// red banner for it would report their own tap back at them.
    func test_aCancelledProviderSheet_isNotReportedAsAnError() {
        let error = authError(.webContextCancelled)
        XCTAssertTrue(AuthErrorMessage.text(for: error).isEmpty, "A cancelled sheet should produce no message")
        XCTAssertFalse(AuthErrorMessage.isWorthReporting(error), "A cancelled sheet should not be reported")
    }

    /// Google Sign-In reports a cancelled sheet in its own error domain, not
    /// as a Firebase `AuthErrorCode`, so it needs its own branch - otherwise
    /// dismissing Google's sheet shows a red "something went wrong" banner.
    func test_googlesOwnCancellation_isNotReportedAsAnError() {
        let cancelled = NSError(domain: "com.google.GIDSignIn", code: -5, userInfo: nil)
        XCTAssertFalse(AuthErrorMessage.isWorthReporting(cancelled))
        XCTAssertTrue(AuthErrorMessage.text(for: cancelled).isEmpty)
    }

    func test_realFailures_areWorthReporting() {
        XCTAssertTrue(AuthErrorMessage.isWorthReporting(authError(.wrongPassword)))
        XCTAssertTrue(AuthErrorMessage.isWorthReporting(authError(.networkError)))
    }
}

// MARK: - Email validation

final class AuthEmailValidatorTests: XCTestCase {

    func test_acceptsOrdinaryAddresses() {
        let valid = [
            "alex@fridgefit.app",
            "a@b.co",
            "first.last@example.com",
            "user+tag@example.co.uk",
            "UPPER@EXAMPLE.COM",
            "name_with_underscore@example.io",
            "digits123@example123.dev",
        ]
        for email in valid {
            XCTAssertTrue(AuthEmailValidator.isValid(email), "\(email) should be accepted")
        }
    }

    /// Deliberately permissive: rejecting a genuinely valid address leaves
    /// the user unable to sign in at all, which is far worse than one wasted
    /// round trip. These are the cases that are unambiguously wrong.
    func test_rejectsOnlyWhatIsUnambiguouslyWrong() {
        let invalid = [
            "",
            "   ",
            "no-at-sign",
            "@example.com",
            "alex@",
            "alex@example",          // no dot in the domain
            "alex@@example.com",     // two at-signs
            "alex@.com",             // domain starts with a dot
            "alex@example.",         // nothing after the final dot
            "alex..b@example.com",   // consecutive dots
            ".alex@example.com",
            "alex.@example.com",
            "alex @example.com",     // whitespace
            "alex@exa mple.com",
        ]
        for email in invalid {
            XCTAssertFalse(AuthEmailValidator.isValid(email), "\(email) should be rejected")
        }
    }

    /// Surrounding whitespace is a paste artefact, not a typo the user
    /// should have to find.
    func test_surroundingWhitespaceIsTolerated() {
        XCTAssertTrue(AuthEmailValidator.isValid("  alex@fridgefit.app  "))
        XCTAssertTrue(AuthEmailValidator.isValid("\nalex@fridgefit.app\n"))
    }
}
