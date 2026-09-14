//
//  LadderService.swift
//  The async ladder: fight other players' builds, driven by the arena's own AI.
//  Brief section 10 ("Async ghost-bot battling gives 90% of the social value for 10% of the
//  netcode risk. No real-time multiplayer.") and docs/stage6-spec.md section 3.
//
//  The shape of it:
//
//  - Every player publishes their current machine to the CloudKit **public** database as a
//    `LadderBuild` record keyed by their owner id.
//  - Opponents are fetched in a window around the player's own rating and cached for the session.
//  - A fight is an ordinary `fight_config` with the ghost as `controller: "ai"`. Nothing about the
//    contract with the arena changes, and nothing is ever real time.
//  - The result moves the player's rating locally (Elo, K = 32) and writes a `LadderResult` record
//    addressed to the ghost's owner, so their rating moves the next time they open the app.
//  - `reconcilePending()` at launch applies the results other people left for this player, then
//    deletes them.
//
//  **The rule that matters: the mode always works.** No iCloud account, no entitlement, no
//  network, CloudKit throwing for a reason nobody predicted, all land in the same place: eight
//  generated ghosts from `CareerEngine.fillerEntrant` at the player's tier, with invented owner
//  names, and a quiet "Offline ladder" label. There is no error alert anywhere in this file and
//  nothing here ever blocks the UI: every CloudKit call is awaited off the main actor and the
//  screen draws whatever it has.
//

import Foundation
import SwiftUI
import CloudKit

@MainActor
@Observable
final class LadderService {

    static let shared = LadderService()

    // MARK: - What the screen draws

    /// One opponent on the ladder. A real one from CloudKit, or a generated ghost when the ladder
    /// is offline. The screen cannot tell the difference and does not need to.
    struct Ghost: Identifiable, Equatable {
        /// The owner id, which is also the CloudKit record name for a real record.
        var id: String
        var displayName: String
        var spec: BuildSpec
        var rating: Int
        var wins: Int
        var losses: Int
        /// True for a made up opponent. A result against one is never written to CloudKit.
        var isGenerated: Bool

        /// "12 fights, 7 wins." or "No fights yet."
        var recordLine: String {
            let fights = wins + losses
            guard fights > 0 else { return "No fights yet." }
            return "\(fights) \(fights == 1 ? "fight" : "fights"), \(wins) \(wins == 1 ? "win" : "wins")."
        }
    }

    /// Where a ladder fight ended up, which is everything the service needs to settle it.
    struct Outcome {
        var opponent: Ghost
        var won: Bool
    }

    /// The player's Elo. 1200 until they have fought.
    private(set) var rating: Int = LadderService.startingRating
    private(set) var wins: Int = 0
    private(set) var losses: Int = 0

    /// The opponents on screen. Never empty once `refresh` has run once.
    private(set) var opponents: [Ghost] = []

    /// True when the list is made up rather than fetched. The screen shows "Offline ladder".
    private(set) var isOffline = true

    /// True while a fetch or a publish is in flight. The screen dims its buttons, it never waits.
    private(set) var isBusy = false

    /// A plain sentence under the heading. Never an error.
    private(set) var statusLine = "Offline ladder."

    /// When the player's own machine was last published, for the screen's own line.
    private(set) var publishedName: String = ""

    // MARK: - Session state

    @ObservationIgnored private var didStart = false
    /// The rating window the cached list was fetched for, so a rating change refetches.
    @ObservationIgnored private var cachedForRating: Int?
    @ObservationIgnored private var cachedAt: Date?
    /// The spec the player last published, so an unchanged machine is not published again.
    @ObservationIgnored private var lastPublishedJSON: String = ""
    /// Set once CloudKit has failed for a reason that will not change this session (no account,
    /// no entitlement), so the screen stops asking.
    @ObservationIgnored private var cloudGaveUp = false

    /// The session cache lives this long. A refresh inside the window returns what it has.
    static let cacheSeconds: TimeInterval = 300
    static let startingRating = 1200
    /// Elo K factor, per docs/stage6-spec.md section 3.
    static let kFactor = 32.0
    /// How far either side of the player's rating an opponent may sit.
    static let ratingWindow = 250
    static let opponentLimit = 20
    static let ghostCount = 8

    private init() {
        let defaults = UserDefaults.standard
        rating = defaults.object(forKey: Key.rating) as? Int ?? Self.startingRating
        wins = defaults.integer(forKey: Key.wins)
        losses = defaults.integer(forKey: Key.losses)
        lastPublishedJSON = defaults.string(forKey: Key.publishedJSON) ?? ""
        publishedName = defaults.string(forKey: Key.publishedName) ?? ""
    }

    // MARK: - CloudKit

    /// The default container, which is the one the entitlement names
    /// (`iCloud.com.radicraft.roboteer`). Created lazily and never touched when CloudKit has been
    /// turned off for this run, because `CKContainer.default()` raises rather than returning nil
    /// when the process has no iCloud entitlement at all.
    @ObservationIgnored private var containerIfAvailable: CKContainer? = {
        guard !ArenaHost.hasLaunchFlag("-noCloudKit") else { return nil }
        // A build signed without the iCloud entitlement (the App ID has no iCloud capability yet)
        // must never touch CKContainer: CloudKit traps instead of returning an error. Read the
        // embedded provisioning profile's entitlements; the simulator has none and is allowed through.
        guard LadderService.buildCarriesCloudKitEntitlement() else { return nil }
        return CKContainer.default()
    }()

    private var publicDatabase: CKDatabase? {
        guard !cloudGaveUp else { return nil }
        return containerIfAvailable?.publicCloudDatabase
    }

    enum RecordType {
        static let build = "LadderBuild"
        static let result = "LadderResult"
    }

    enum Field {
        static let ownerID = "ownerID"
        static let displayName = "displayName"
        static let buildJSON = "buildJSON"
        static let rating = "rating"
        static let wins = "wins"
        static let losses = "losses"
        static let updatedAt = "updatedAt"

        static let targetOwnerID = "targetOwnerID"
        static let challengerName = "challengerName"
        static let won = "won"
        static let ratingDelta = "ratingDelta"
        static let createdAt = "createdAt"
    }

    // MARK: - Launch

    /// Called once at launch, from the menu. Reconciles anything other players left for this
    /// player and then leaves the ladder alone until the screen is opened.
    func start() {
        guard !didStart else { return }
        didStart = true
        Task { await reconcilePending() }
    }

    // MARK: - Fetching opponents

    /// Fill `opponents` for this tier. Cached for the session: a second call inside five minutes
    /// at the same rating returns what it already has, which is what the spec asks for.
    func refresh(tier: CareerTier, force: Bool = false) async {
        if !force,
           let cachedForRating, cachedForRating == rating,
           let cachedAt, Date().timeIntervalSince(cachedAt) < Self.cacheSeconds,
           !opponents.isEmpty {
            return
        }

        isBusy = true
        defer { isBusy = false }

        let fetched = await fetchOpponents(nearRating: rating, limit: Self.opponentLimit)
        if let fetched, !fetched.isEmpty {
            opponents = fetched
            isOffline = false
            statusLine = "\(fetched.count) \(fetched.count == 1 ? "machine" : "machines") near your rating."
        } else {
            opponents = generatedGhosts(tier: tier)
            isOffline = true
            statusLine = "Offline ladder."
        }
        cachedForRating = rating
        cachedAt = Date()
    }

    /// A query in a rating window. Returns nil when CloudKit could not answer at all, which is
    /// the signal to fall back; an empty array means the ladder is simply thin up here, and that
    /// falls back too because an empty ladder is not a mode.
    func fetchOpponents(nearRating centre: Int, limit: Int) async -> [Ghost]? {
        guard let database = publicDatabase else { return nil }
        let me = GameCenterService.shared.ownerID

        let low = centre - Self.ratingWindow
        let high = centre + Self.ratingWindow
        let predicate = NSPredicate(format: "%K >= %@ AND %K <= %@",
                                    Field.rating, NSNumber(value: low),
                                    Field.rating, NSNumber(value: high))
        let query = CKQuery(recordType: RecordType.build, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: Field.updatedAt, ascending: false)]

        do {
            let (matches, _) = try await database.records(matching: query, resultsLimit: limit)
            var found: [Ghost] = []
            for (_, result) in matches {
                guard let record = try? result.get() else { continue }
                guard let ghost = Self.ghost(from: record) else { continue }
                guard ghost.id != me else { continue }
                found.append(ghost)
            }
            spikeLog.info("ladder fetched \(found.count, privacy: .public) opponents between \(low, privacy: .public) and \(high, privacy: .public)")
            return found
        } catch {
            noteCloudFailure(error, doing: "fetching opponents")
            return nil
        }
    }

    // MARK: - Publishing

    /// Put the player's selected machine on the ladder. Silent, and never blocking: the screen
    /// says what it said before until this comes back.
    func publish(build: BotBuild) async {
        let spec = build.spec
        let json = Self.specJSON(spec)
        publishedName = build.name
        UserDefaults.standard.set(build.name, forKey: Key.publishedName)

        guard let database = publicDatabase else {
            statusLine = "Offline ladder."
            return
        }

        isBusy = true
        defer { isBusy = false }

        let me = GameCenterService.shared.ownerID
        let name = GameCenterService.shared.displayName
        let recordID = CKRecord.ID(recordName: me)

        do {
            let record: CKRecord
            if let existing = try? await database.record(for: recordID) {
                record = existing
            } else {
                record = CKRecord(recordType: RecordType.build, recordID: recordID)
            }
            record[Field.ownerID] = me as CKRecordValue
            record[Field.displayName] = name as CKRecordValue
            record[Field.buildJSON] = json as CKRecordValue
            record[Field.rating] = rating as CKRecordValue
            record[Field.wins] = wins as CKRecordValue
            record[Field.losses] = losses as CKRecordValue
            record[Field.updatedAt] = Date() as CKRecordValue
            _ = try await database.save(record)

            lastPublishedJSON = json
            UserDefaults.standard.set(json, forKey: Key.publishedJSON)
            isOffline = false
            statusLine = "\(build.name) is on the ladder."
            spikeLog.info("ladder published \(build.name, privacy: .public) at \(self.rating, privacy: .public)")
        } catch {
            noteCloudFailure(error, doing: "publishing the build")
            statusLine = "Offline ladder."
        }
    }

    /// True when the machine on screen is not the one that was published, so the screen can say so
    /// without the player having to remember.
    func isPublished(_ build: BotBuild) -> Bool {
        !lastPublishedJSON.isEmpty && lastPublishedJSON == Self.specJSON(build.spec)
    }

    // MARK: - Results

    /// Settle a ladder fight. The rating moves here, locally, whatever CloudKit is doing, and the
    /// two writes that need the network are fired afterwards and may quietly fail.
    @discardableResult
    func submit(result: Outcome) -> Int {
        let delta = Self.eloDelta(mine: rating, theirs: result.opponent.rating, won: result.won)
        rating = max(100, rating + delta)
        if result.won { wins += 1 } else { losses += 1 }
        save()

        // A generated ghost has no owner to tell.
        guard !result.opponent.isGenerated else {
            spikeLog.info("ladder result against a generated ghost, rating \(self.rating, privacy: .public)")
            return delta
        }

        let opponent = result.opponent
        let challenger = GameCenterService.shared.displayName
        // The ghost's own rating moves the other way when they next open the app.
        let theirDelta = Self.eloDelta(mine: opponent.rating, theirs: rating - delta, won: !result.won)
        Task {
            await pushResult(targetOwnerID: opponent.id,
                             challengerName: challenger,
                             challengerWon: result.won,
                             ratingDelta: theirDelta)
            await pushOwnRating()
        }
        return delta
    }

    /// Write the `LadderResult` the other player reconciles on their next launch.
    private func pushResult(targetOwnerID: String, challengerName: String, challengerWon: Bool, ratingDelta: Int) async {
        guard let database = publicDatabase else { return }
        let record = CKRecord(recordType: RecordType.result)
        record[Field.targetOwnerID] = targetOwnerID as CKRecordValue
        record[Field.challengerName] = challengerName as CKRecordValue
        record[Field.won] = (challengerWon ? 1 : 0) as CKRecordValue
        record[Field.ratingDelta] = ratingDelta as CKRecordValue
        record[Field.createdAt] = Date() as CKRecordValue
        do {
            _ = try await database.save(record)
            spikeLog.info("ladder result written for \(targetOwnerID, privacy: .public)")
        } catch {
            noteCloudFailure(error, doing: "writing a ladder result")
        }
    }

    /// The player's own record carries the new rating and record.
    private func pushOwnRating() async {
        guard let database = publicDatabase else { return }
        let me = GameCenterService.shared.ownerID
        let recordID = CKRecord.ID(recordName: me)
        do {
            guard let record = try? await database.record(for: recordID) else { return }
            record[Field.rating] = rating as CKRecordValue
            record[Field.wins] = wins as CKRecordValue
            record[Field.losses] = losses as CKRecordValue
            record[Field.updatedAt] = Date() as CKRecordValue
            _ = try await database.save(record)
        } catch {
            noteCloudFailure(error, doing: "updating the ladder record")
        }
    }

    // MARK: - Reconciling

    /// Apply every `LadderResult` addressed to this player, then delete them. Run once at launch.
    /// Everything about it is best effort: a result that cannot be deleted is simply applied once
    /// more next launch, which is why the delete and the apply happen together per record.
    func reconcilePending() async {
        guard let database = publicDatabase else { return }
        let me = GameCenterService.shared.ownerID
        let predicate = NSPredicate(format: "%K == %@", Field.targetOwnerID, me)
        let query = CKQuery(recordType: RecordType.result, predicate: predicate)

        do {
            let (matches, _) = try await database.records(matching: query, resultsLimit: 50)
            var applied = 0
            var toDelete: [CKRecord.ID] = []
            for (recordID, result) in matches {
                guard let record = try? result.get() else { continue }
                let delta = record[Field.ratingDelta] as? Int ?? 0
                let challengerWon = (record[Field.won] as? Int ?? 0) == 1
                rating = max(100, rating + delta)
                // The challenger won means this player's ghost lost.
                if challengerWon { losses += 1 } else { wins += 1 }
                toDelete.append(recordID)
                applied += 1
            }
            guard applied > 0 else { return }
            save()
            spikeLog.info("ladder reconciled \(applied, privacy: .public) pending results, rating \(self.rating, privacy: .public)")

            for recordID in toDelete {
                _ = try? await database.deleteRecord(withID: recordID)
            }
            await pushOwnRating()
            GameCenterService.shared.report(leaderboard: GameCenterService.Leaderboard.ladderRating, score: rating)
        } catch {
            noteCloudFailure(error, doing: "reconciling pending results")
        }
    }

    // MARK: - Elo

    /// K = 32, the classic. Rounded away from zero so a win is never worth nothing.
    static func eloDelta(mine: Int, theirs: Int, won: Bool) -> Int {
        let expected = 1.0 / (1.0 + pow(10.0, Double(theirs - mine) / 400.0))
        let actual = won ? 1.0 : 0.0
        let raw = kFactor * (actual - expected)
        let rounded = Int(raw.rounded())
        if rounded == 0 { return won ? 1 : -1 }
        return rounded
    }

    // MARK: - The fallback

    /// Eight made up machines at the player's tier, from the career's own filler generator, with
    /// invented roboteer names and ratings spread around the player's own. Deterministic from the
    /// player's rating and the tier, so the list does not reshuffle every time the screen appears.
    func generatedGhosts(tier: CareerTier) -> [Ghost] {
        var rng = SeededRandom(seed: UInt64(bitPattern: Int64(rating &* 7919 &+ tier.index &* 104729)))
        let offsets = [-140, -95, -55, -20, 15, 55, 105, 165]
        var ghosts: [Ghost] = []
        for index in 0..<Self.ghostCount {
            let entrant = CareerEngine.fillerEntrant(index: index, tier: tier, rng: &rng)
            let jitter = rng.index(31) - 15
            let offset = index < offsets.count ? offsets[index] : 0
            ghosts.append(Ghost(
                id: "ghost-\(tier.rawValue)-\(index)",
                displayName: entrant.roboteer,
                spec: entrant.spec,
                rating: max(100, rating + offset + jitter),
                wins: rng.index(24),
                losses: rng.index(20),
                isGenerated: true
            ))
        }
        return ghosts.sorted { $0.rating > $1.rating }
    }

    // MARK: - Records in and out

    private static func ghost(from record: CKRecord) -> Ghost? {
        let owner = (record[Field.ownerID] as? String) ?? record.recordID.recordName
        guard !owner.isEmpty else { return nil }
        guard let json = record[Field.buildJSON] as? String, let spec = specFromJSON(json) else { return nil }
        let name = (record[Field.displayName] as? String) ?? "Roboteer"
        return Ghost(
            id: owner,
            displayName: name.isEmpty ? "Roboteer" : name,
            spec: spec,
            rating: record[Field.rating] as? Int ?? startingRating,
            wins: record[Field.wins] as? Int ?? 0,
            losses: record[Field.losses] as? Int ?? 0,
            isGenerated: false
        )
    }

    /// `BuildSpec` as text. Sorted keys, so the same machine always encodes to the same string and
    /// "is this already published" is a string comparison (docs/stage5-swift-notes.md).
    static func specJSON(_ spec: BuildSpec) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(spec), let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    /// A published machine, read back and made legal before anything fights it, because the
    /// catalogue may have changed under it since it was published.
    static func specFromJSON(_ json: String) -> BuildSpec? {
        guard let data = json.data(using: .utf8),
              let spec = try? JSONDecoder().decode(BuildSpec.self, from: data) else { return nil }
        return CareerEngine.legalise(spec)
    }

    // MARK: - Failure

    /// One place for every CloudKit failure. It logs, it decides whether to stop asking this
    /// session, and it never shows the player anything.
    private func noteCloudFailure(_ error: Error, doing what: String) {
        spikeLog.info("ladder could not finish \(what, privacy: .public): \(error.localizedDescription, privacy: .public)")
        guard let ckError = error as? CKError else { return }
        switch ckError.code {
        case .notAuthenticated, .permissionFailure, .badContainer, .missingEntitlement, .managedAccountRestricted:
            // Nothing this session is going to fix these, so stop knocking.
            cloudGaveUp = true
            isOffline = true
        default:
            break
        }
    }

    // MARK: - Persistence

    private enum Key {
        static let rating = "ladder.rating"
        static let wins = "ladder.wins"
        static let losses = "ladder.losses"
        static let publishedJSON = "ladder.publishedJSON"
        static let publishedName = "ladder.publishedName"
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(rating, forKey: Key.rating)
        defaults.set(wins, forKey: Key.wins)
        defaults.set(losses, forKey: Key.losses)
    }

    /// QA only: back to an unfought ladder.
    func resetForQA() {
        rating = Self.startingRating
        wins = 0
        losses = 0
        lastPublishedJSON = ""
        publishedName = ""
        cachedForRating = nil
        cachedAt = nil
        opponents = []
        save()
        UserDefaults.standard.removeObject(forKey: Key.publishedJSON)
        UserDefaults.standard.removeObject(forKey: Key.publishedName)
    }

    /// True when the embedded provisioning profile grants iCloud container identifiers, or when there
    /// is no embedded profile at all (simulator, where CloudKit is mocked and safe to call).
    static func buildCarriesCloudKitEntitlement() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1) else { return false }
        guard let start = text.range(of: "<plist"), let end = text.range(of: "</plist>") else { return false }
        let plistText = String(text[start.lowerBound..<end.upperBound])
        guard let plistData = plistText.data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any] else { return false }
        return entitlements["com.apple.developer.icloud-container-identifiers"] != nil
        #endif
    }
}
