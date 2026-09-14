//
//  EventCatalogue.swift
//  The five side events, their rewards and their records. Brief section 10, docs/stage6-spec.md
//  section 1.
//
//  The five are data, not code: `Shared/parts.json` gains one top level `events` array, read here
//  the same way `Catalogue` and `CareerCatalogue` read their own blocks. Adding a sixth event is a
//  catalogue edit plus a Godot rules file, not a Swift edit.
//
//  Every event is behind the wall (`Gates.sideEventsAvailable`), so the rewards are deliberately
//  drawn from the late tier drips: clearing an event brings a part forward, it never invents one.
//

import Foundation
import SwiftData

// MARK: - The modes

/// `rules.mode` for a side event. The raw value is what goes on the wire and what the Godot side
/// switches on (`Arena/fight/events/<mode>.gd`).
enum EventMode: String, CaseIterable, Identifiable, Hashable {
    case sumo
    case gauntlet
    case pinball
    case football
    case wallSmash = "wall_smash"

    var id: String { rawValue }

    /// Sumo and Football need a second machine on the floor. The other three are the player alone
    /// against the arena, and the gauntlet's boss is spawned by the arena, not sent by the shell.
    var needsOpponent: Bool {
        self == .sumo || self == .football
    }

    /// Whether the headline number is a time rather than a score. The gauntlet and wall smash are
    /// both raced, so a lower time is a better run and the score is a tie breaker.
    var isRaced: Bool {
        self == .gauntlet || self == .wallSmash
    }

    /// What the number on the card is called.
    var scoreWord: String {
        switch self {
        case .sumo: return "Falls"
        case .gauntlet: return "Points"
        case .pinball: return "Score"
        case .football: return "Goals"
        case .wallSmash: return "Walls"
        }
    }
}

// MARK: - The catalogue

/// The `events` block of `Shared/parts.json`, read once.
struct EventCatalogue {

    struct Entry: Identifiable, Equatable {
        let id: String
        let name: String
        /// One line, plain, no em dashes. It is the only thing the card says about the event.
        let pitch: String
        /// The blueprint handed over the first time the event is cleared.
        let rewardPart: String
        /// The clock the arena is asked for, in seconds.
        let clockSeconds: Int

        var mode: EventMode? { EventMode(rawValue: id) }

        /// "Rear wedge", from the part catalogue, so a renamed part renames itself here.
        var rewardName: String { CareerEngine.partName(rewardPart) }
    }

    let events: [Entry]

    func entry(_ id: String) -> Entry? { events.first { $0.id == id } }
    func entry(_ mode: EventMode) -> Entry? { entry(mode.rawValue) }

    /// The five in catalogue order, with anything the catalogue does not know about dropped, so a
    /// Godot mode with no card cannot be started from here.
    var known: [Entry] { events.filter { $0.mode != nil } }

    static let shared: EventCatalogue = load()

    static func load() -> EventCatalogue {
        guard let url = Bundle.main.url(forResource: "parts", withExtension: "json"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let root = JSONValue.parse(text) else {
            assertionFailure("parts.json is missing from the bundle or did not parse")
            return EventCatalogue(events: fallback)
        }
        let items = (root["events"]?.items ?? []).compactMap { value -> Entry? in
            guard let id = value["id"]?.stringValue else { return nil }
            return Entry(
                id: id,
                name: value["name"]?.stringValue ?? id.capitalizedFirst,
                pitch: value["pitch"]?.stringValue ?? "",
                rewardPart: value["reward_part"]?.stringValue ?? "",
                clockSeconds: value["clock_s"]?.intValue ?? 90
            )
        }
        return EventCatalogue(events: items.isEmpty ? fallback : items)
    }

    /// Used only when the `events` key is missing, so the screen is never empty in a build made
    /// from an older catalogue.
    static let fallback: [Entry] = [
        Entry(id: "sumo", name: "Sumo",
              pitch: "Push the other machine off a six metre platform. Best of three.",
              rewardPart: "rear_wedge", clockSeconds: 90),
        Entry(id: "gauntlet", name: "Gauntlet",
              pitch: "Run the hazard corridor against the clock.",
              rewardPart: "skirts", clockSeconds: 90),
        Entry(id: "pinball", name: "Pinball",
              pitch: "Sixty seconds on the table.",
              rewardPart: "magnets", clockSeconds: 60),
        Entry(id: "football", name: "Football",
              pitch: "One ball, two goals, one opponent.",
              rewardPart: "scoop", clockSeconds: 90),
        Entry(id: "wall_smash", name: "Wall Smash",
              pitch: "Five walls stand between you and the far end.",
              rewardPart: "counterweight", clockSeconds: 90)
    ]
}

// MARK: - The result the arena sends

/// `event_result` {mode, score, cleared, time_s, details}. It replaces `fight_result` for the five
/// side events; a side event never sends judges, scrap or a winner.
struct EventResult: Equatable {

    var mode: String = ""
    var score: Int = 0
    var cleared: Bool = false
    var timeSeconds: Double = 0
    /// Whatever the mode wanted to add: goals for and against, walls broken, damage taken. Read as
    /// text so a new key from the arena shows up rather than being dropped.
    var details: [String: String] = [:]

    var eventMode: EventMode? { EventMode(rawValue: mode) }

    init() {}

    init?(json: String) {
        guard let root = JSONValue.parse(json) else { return nil }
        mode = root["mode"]?.stringValue ?? ""
        score = root["score"]?.intValue ?? 0
        cleared = root["cleared"]?.boolValue ?? false
        timeSeconds = root["time_s"]?.doubleValue ?? 0
        for member in (root["details"]?.members ?? []) {
            if let text = member.value.stringValue {
                details[member.key] = text
            } else if let number = member.value.doubleValue {
                details[member.key] = number == number.rounded()
                    ? String(Int(number))
                    : String(format: "%.2f", number)
            } else if let flag = member.value.boolValue {
                details[member.key] = flag ? "yes" : "no"
            }
        }
    }

    /// "1:04" or "38.4 s".
    var timeLine: String {
        let whole = Int(timeSeconds.rounded())
        if whole >= 60 { return String(format: "%d:%02d", whole / 60, whole % 60) }
        return String(format: "%.1f s", timeSeconds)
    }
}

// MARK: - The record

/// One row per mode: the best the player has ever done at it. Not a fight log and not a career
/// state, because an event is neither: it has no purse, no repair bill and no bracket.
@Model
final class EventRecord {

    /// The `EventMode` raw value.
    var mode: String = ""
    /// The highest score ever scored at this event.
    var bestScore: Int = 0
    /// The fastest cleared run, in seconds. Zero means it has never been cleared.
    var bestTimeS: Double = 0
    /// Whether the reward blueprint has been earned. Once true it never goes back.
    var cleared: Bool = false
    var plays: Int = 0
    var lastPlayed: Date = Date()

    init(mode: String = "") {
        self.mode = mode
        self.lastPlayed = Date()
    }

    var eventMode: EventMode? { EventMode(rawValue: mode) }

    /// "Best 4200" or "Best 38.4 s", or nothing at all before the first run.
    func bestLine(_ mode: EventMode) -> String? {
        guard plays > 0 else { return nil }
        if mode.isRaced {
            guard cleared, bestTimeS > 0 else { return "\(mode.scoreWord.uppercased()) \(bestScore)" }
            return String(format: "BEST %.1f s", bestTimeS)
        }
        return "BEST \(bestScore)"
    }
}

// MARK: - The store

/// Reading and writing the event records, and the one place an event hands over a blueprint.
enum EventStore {

    /// What one run changed, so the result sheet knows what to celebrate.
    struct Outcome: Equatable {
        var isNewBest = false
        var firstClear = false
        /// The blueprint id handed over, or nil when nothing was earned (already held, or the run
        /// was not a clear).
        var newBlueprint: String?
    }

    static func record(for mode: EventMode, in context: ModelContext) -> EventRecord {
        let all = (try? context.fetch(FetchDescriptor<EventRecord>())) ?? []
        if let existing = all.first(where: { $0.mode == mode.rawValue }) { return existing }
        let fresh = EventRecord(mode: mode.rawValue)
        context.insert(fresh)
        return fresh
    }

    static func records(in context: ModelContext) -> [String: EventRecord] {
        let all = (try? context.fetch(FetchDescriptor<EventRecord>())) ?? []
        return Dictionary(all.map { ($0.mode, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Write one run into the record, hand over the blueprint on a first clear, and log the run.
    /// The blueprint goes into `CareerState.blueprints` through `CareerStore`, which is the one
    /// place blueprints are ever held, so a part earned in an event is a part the builder offers.
    @discardableResult
    static func apply(
        _ result: EventResult,
        mode: EventMode,
        botName: String,
        resultJSON: String,
        in context: ModelContext
    ) -> Outcome {
        var outcome = Outcome()
        let record = record(for: mode, in: context)
        record.plays += 1
        record.lastPlayed = Date()

        if result.score > record.bestScore {
            record.bestScore = result.score
            outcome.isNewBest = true
        }
        if result.cleared, result.timeSeconds > 0 {
            if record.bestTimeS == 0 || result.timeSeconds < record.bestTimeS {
                record.bestTimeS = result.timeSeconds
                if mode.isRaced { outcome.isNewBest = true }
            }
        }
        if result.cleared, !record.cleared {
            record.cleared = true
            outcome.firstClear = true
            if let part = EventCatalogue.shared.entry(mode)?.rewardPart, !part.isEmpty {
                if awardBlueprint(part, in: context) { outcome.newBlueprint = part }
            }
        }

        log(result, mode: mode, botName: botName, resultJSON: resultJSON, in: context)
        try? context.save()
        return outcome
    }

    /// The blueprint goes to the career, because that is where every blueprint lives. Returns
    /// false when the player already held it, so the flourish is only shown for something new.
    @discardableResult
    static func awardBlueprint(_ partID: String, in context: ModelContext) -> Bool {
        let state = CareerStore.state(in: context)
        guard !state.blueprints.contains(partID) else { return false }
        state.blueprints.append(partID)
        try? context.save()
        spikeLog.info("event blueprint \(partID, privacy: .public) handed over")
        return true
    }

    /// An event run is written into `FightLog` like any other fight, so the history is one list.
    /// `round` is -1 and `opponentID` is the mode, which is how the replay list tells the two
    /// apart without a schema change.
    private static func log(
        _ result: EventResult,
        mode: EventMode,
        botName: String,
        resultJSON: String,
        in context: ModelContext
    ) {
        let entry = EventCatalogue.shared.entry(mode)
        let log = FightLog()
        log.date = Date()
        log.round = -1
        log.opponentID = mode.rawValue
        log.opponentName = entry?.name ?? mode.rawValue.capitalizedFirst
        log.botName = botName
        log.outcome = result.cleared ? "cleared" : "event"
        log.didWin = result.cleared
        log.arena = mode.rawValue
        log.resultJSON = resultJSON
        log.replayJSON = ReplayPayload.block(from: resultJSON)
        log.configJSON = ArenaHost.shared.lastFightConfigJSON
        context.insert(log)
    }
}

// MARK: - The configuration an event sends

/// A side event is an ordinary `FightConfig` with `rules.mode` set to the event and the arena id
/// equal to the mode id, so `Arena/arena/events/<mode>.tscn` is selectable from one string.
enum EventFightConfig {

    static let playerID = "player-1"
    static let opponentID = "ai-1"

    static func json(
        mode: EventMode,
        player: [String: Any],
        opponent: [String: Any]?,
        clockSeconds: Int,
        seed: Int,
        safeArea: SafeAreaPixels
    ) -> String {
        var bots: [[String: Any]] = [player]
        if let opponent { bots.append(opponent) }
        let root: [String: Any] = [
            "schema": 1,
            "seed": seed,
            "arena": mode.rawValue,
            "rules": [
                "mode": mode.rawValue,
                "duration_s": clockSeconds,
                "ko_count_s": 10
            ],
            "presentation": [
                "safe_area_px": [
                    "left": safeArea.left,
                    "top": safeArea.top,
                    "right": safeArea.right,
                    "bottom": safeArea.bottom
                ],
                "haptics": RoboteerSettings.shared.haptics
            ],
            "debug": ["opponent_ai": ArenaHost.opponentAI],
            "bots": bots
        ]
        return JSONText.string(from: root)
    }

    /// The machine the player fights in Sumo and Football: a filler entrant from the career
    /// engine at the tier the player has reached, so it is a real legal build and it gets harder
    /// as the career does.
    static func fillerOpponent(tier: CareerTier, seed: Int) -> [String: Any] {
        var rng = SeededRandom(seed: seed)
        let entrant = CareerEngine.fillerEntrant(index: abs(seed) % 24, tier: tier, rng: &rng)
        return entrant.spec.toBotConfig(id: opponentID, controller: "ai")
    }
}
