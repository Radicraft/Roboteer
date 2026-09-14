//
//  GameCenterService.swift
//  Game Center: who the player is on the ladder, and the two leaderboards.
//  Brief section 12 ("GameKit: Game Center leaderboards, async ladder identity") and
//  docs/stage6-spec.md section 3.
//
//  Three rules this file keeps:
//
//  1. **Every failure is silent.** Game Center is not a feature the player asked for. If the
//     player is not signed in, if the device has no network, if the leaderboards have not been
//     created in App Store Connect yet, the game carries on exactly as before and the only trace
//     is a log line. Nothing here ever shows an alert or blocks a screen.
//  2. **There is always a name.** A player who declines Game Center still has an identity on the
//     ladder: a local guest name like "Roboteer 4821", generated once and persisted, so their
//     published machine keeps the same name for the life of the install.
//  3. **There is always an owner id.** `ownerID` is the Game Center player id when the player is
//     authenticated and a persisted local UUID otherwise. It is the key the ladder records hang
//     off, so it must never change under a player who has one.
//

import Foundation
import SwiftUI
import GameKit
import UIKit

@MainActor
@Observable
final class GameCenterService {

    static let shared = GameCenterService()

    /// The two leaderboard ids. They have to match App Store Connect exactly or a submission is
    /// silently dropped, which is why they are constants in one place.
    enum Leaderboard {
        /// The ladder rating, Elo, starting at 1200.
        static let ladderRating = "ladder_rating"
        /// Career wins, all tiers.
        static let careerWins = "career_wins"
    }

    /// True once `GKLocalPlayer.local.isAuthenticated` has come back true. False while the
    /// handler has not run, and false forever for a player who declined.
    private(set) var isAuthenticated = false

    /// What the ladder prints next to this player's machine. The Game Center alias when there is
    /// one, the persisted guest name otherwise. Never empty.
    private(set) var displayName: String = ""

    /// The key every ladder record hangs off. Stable for the life of the install.
    private(set) var ownerID: String = ""

    /// A plain sentence for the ladder's own status line. Never an error, never a nag.
    private(set) var statusLine: String = ""

    @ObservationIgnored private var didStart = false
    /// Set while the Game Center sign in sheet is on screen, so a second authenticate attempt
    /// cannot present a second one.
    @ObservationIgnored private var isPresentingAuth = false

    private init() {
        displayName = Self.guestName
        ownerID = Self.localOwnerID
    }

    // MARK: - Launch

    /// Authenticate on launch. Idempotent: the handler is installed once for the life of the
    /// process, which is what GameKit asks for.
    func start() {
        guard !didStart else { return }
        didStart = true
        guard !ArenaHost.hasLaunchFlag("-noGameCenter") else {
            statusLine = "Game Center is off for this run."
            spikeLog.info("game center skipped, -noGameCenter")
            return
        }

        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handleAuthentication(viewController: viewController, error: error)
            }
        }
    }

    private func handleAuthentication(viewController: UIViewController?, error: Error?) {
        if let viewController {
            present(viewController)
            return
        }
        if let error {
            // A player who has never signed in gets an error here every launch. It is not a
            // failure of the game and the player is never told.
            isAuthenticated = false
            statusLine = "Playing as \(displayName)."
            spikeLog.info("game center did not authenticate: \(error.localizedDescription, privacy: .public)")
            return
        }

        let local = GKLocalPlayer.local
        isAuthenticated = local.isAuthenticated
        if isAuthenticated {
            let alias = local.alias.trimmingCharacters(in: .whitespacesAndNewlines)
            displayName = alias.isEmpty ? Self.guestName : alias
            let identifier = local.gamePlayerID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !identifier.isEmpty { ownerID = identifier }
            statusLine = "Signed in as \(displayName)."
            spikeLog.info("game center authenticated as \(self.displayName, privacy: .public)")
        } else {
            displayName = Self.guestName
            ownerID = Self.localOwnerID
            statusLine = "Playing as \(displayName)."
            spikeLog.info("game center is not signed in, playing as \(self.displayName, privacy: .public)")
        }
    }

    /// GameKit hands back a view controller when it wants to ask the player to sign in. It has to
    /// be presented from the key window, because this app has no view controller of its own to
    /// hang it off: SwiftUI owns the whole window.
    private func present(_ viewController: UIViewController) {
        guard !isPresentingAuth else { return }
        guard let root = Self.topViewController() else {
            spikeLog.info("game center asked to present a sign in sheet and there was no window")
            return
        }
        isPresentingAuth = true
        viewController.presentationController?.delegate = nil
        root.present(viewController, animated: true) { [weak self] in
            // The sheet is up. GameKit calls the handler again when it closes.
            MainActor.assumeIsolated { self?.isPresentingAuth = false }
        }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = active?.windows.first { $0.isKeyWindow } ?? active?.windows.first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }

    // MARK: - Leaderboards

    /// Report a score. Silent on every failure, including the common one of the leaderboard not
    /// existing in App Store Connect yet.
    func report(leaderboard: String, score: Int) {
        guard isAuthenticated else {
            spikeLog.info("leaderboard \(leaderboard, privacy: .public) not reported, not signed in")
            return
        }
        let player = GKLocalPlayer.local
        Task.detached(priority: .utility) {
            do {
                try await GKLeaderboard.submitScore(
                    score,
                    context: 0,
                    player: player,
                    leaderboardIDs: [leaderboard]
                )
                spikeLog.info("leaderboard \(leaderboard, privacy: .public) reported \(score, privacy: .public)")
            } catch {
                spikeLog.info("leaderboard \(leaderboard, privacy: .public) was not accepted: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The two the ladder reports after every fight.
    func reportLadder(rating: Int, careerWins: Int) {
        report(leaderboard: Leaderboard.ladderRating, score: rating)
        report(leaderboard: Leaderboard.careerWins, score: careerWins)
    }

    // MARK: - The guest identity

    private enum Key {
        static let guestName = "ladder.guestName"
        static let localOwnerID = "ladder.localOwnerID"
    }

    /// "Roboteer 4821". Generated once and kept, so a guest's published machine does not change
    /// its name every launch.
    static var guestName: String {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: Key.guestName), !saved.isEmpty { return saved }
        let name = "Roboteer \(Int.random(in: 1000...9999))"
        defaults.set(name, forKey: Key.guestName)
        return name
    }

    /// A stable local id for a player with no Game Center account.
    static var localOwnerID: String {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: Key.localOwnerID), !saved.isEmpty { return saved }
        let identifier = "local-" + UUID().uuidString
        defaults.set(identifier, forKey: Key.localOwnerID)
        return identifier
    }
}
