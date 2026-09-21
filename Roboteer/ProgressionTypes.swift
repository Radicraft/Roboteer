//
//  ProgressionTypes.swift
//  The shared contract of wave P (docs/brief-v5-progression.md, docs/wave-p-contracts.md): the
//  value types every screen and the engine agree on. Written by the coordinator before the wave
//  so nine agents compile against one shape. Agent A (`ProgressionEngine.swift`) fills the
//  engine; B1 and B2 read these on screen; C's arena fields are decoded into `MatchReport`.
//
//  Rules: pure values, Codable where they are stored, no SwiftUI, no SwiftData, no numbers of
//  their own (every number comes from `Shared/parts.json` `progression`).
//

import Foundation

// MARK: - Level

/// One continuous career bar (brief v5 section 7).
struct LevelState: Codable, Equatable {
    var points: Int = 0
    var pointsPerLevel: Int = 100
    var cap: Int = 100

    /// 1 at the start, never above `cap`.
    var level: Int { min(cap, 1 + points / max(1, pointsPerLevel)) }
    /// Points into the current level, 0 ..< pointsPerLevel (pointsPerLevel when capped).
    var pointsIntoLevel: Int { level >= cap ? pointsPerLevel : points % max(1, pointsPerLevel) }
    /// 0 to 1 along the bar of the current level. Full when capped.
    var fraction: Double { level >= cap ? 1 : Double(pointsIntoLevel) / Double(max(1, pointsPerLevel)) }
    var isCapped: Bool { level >= cap }
}

// MARK: - Series

/// Where the campaign stands (brief v5 section 4). Series and matches are 0-based in code and
/// 1-based on screen ("Series 1: 2/4 matches").
struct SeriesProgress: Codable, Equatable {
    /// 0 to 4, the tier id's index.
    var seriesIndex: Int = 0
    /// 0 to 3: the next match to fight in the current Series. 4 means the Series is complete.
    var matchIndex: Int = 0
    /// Attempts at the CURRENT match so far (0 before the first try). Reset when a match is won.
    var attempts: Int = 0
    /// True once the Series 5 final has been won. Won matches may then be replayed.
    var campaignComplete: Bool = false

    static let matchesPerSeries = 4
    static let seriesCount = 5

    var seriesNumber: Int { seriesIndex + 1 }
    var matchNumber: Int { min(matchIndex, SeriesProgress.matchesPerSeries - 1) + 1 }
    var matchesWonInSeries: Int { min(matchIndex, SeriesProgress.matchesPerSeries) }
    var seriesComplete: Bool { matchIndex >= SeriesProgress.matchesPerSeries }
    /// "Series 1: 2/4 matches"
    var line: String { "Series \(seriesNumber): \(matchesWonInSeries)/\(SeriesProgress.matchesPerSeries) matches" }
}

/// One match on a Series strip, for the Series screen and the full board.
struct SeriesMatchSlot: Equatable, Identifiable {
    enum State: String { case won, next, locked, replayable }
    var index: Int
    var opponentName: String
    var opponentLiveryHex: String
    var isFinal: Bool
    var state: State
    /// "Knockout at 34 s" once won, else empty.
    var note: String = ""
    var id: Int { index }
}

// MARK: - The next match

/// Everything the next-match card prints and everything the fight config needs, made in one place
/// (the same job `NextFight` did for the season). Agent A builds it; B1 sends it; B2 prints it.
struct NextMatch: Equatable {
    var tier: CareerTier
    var seriesIndex: Int
    var matchIndex: Int
    var isFinal: Bool
    /// True when this is a replay of a match already won (campaign complete).
    var isReplay: Bool
    var attempts: Int

    var opponent: CareerEntrant
    var arena: String
    var arenaName: String

    var houseBotID: String
    var houseBotName: String
    var houseBotSpeed: Double
    var houseBotLine: String

    var scoutingLine: String
    var grudgeLine: String
    var aiSkill: String
    var temperament: String

    /// `rules.scrap` for the fight config, from `progression.series[n].scrap`.
    var scrapRules: ScrapRules
    /// What a win pays in Level points (already scaled for a replay).
    var winPoints: Int
    /// What the chosen machine still owes in repairs, or 0.
    var repairsDue: Int = 0

    var seriesNumber: Int { seriesIndex + 1 }
    var matchNumber: Int { matchIndex + 1 }
    /// "Series 2, match 3" or "Series 2 final".
    var title: String { isFinal ? "Series \(seriesNumber) final" : "Series \(seriesNumber), match \(matchNumber)" }
    var partsLine: String { opponent.spec.partsLine }
    /// The seed this attempt is fought with: deterministic per career seed, match and attempt.
    func seed(careerSeed: Int) -> Int {
        var value = careerSeed &* 1_000_003
        value = value &+ seriesIndex &* 10_007 &+ matchIndex &* 101 &+ attempts
        return abs(value % 2_000_000_000)
    }
}

/// `rules.scrap` on the wire (contracts file, section "Scrap").
struct ScrapRules: Codable, Equatable {
    var base: Int = 0
    var damageFull: Int = 0
    var survivor: Int = 0
    var survivorMin: Double = 0.7
    var flawless: Int = 0

    var asDictionary: [String: Any] {
        ["base": base, "damage_full": damageFull, "survivor": survivor, "survivor_min": survivorMin, "flawless": flawless]
    }
}

// MARK: - The match report

/// One part's condition after the match, for the per-part list (brief v5 section 5).
struct PartCondition: Equatable, Identifiable {
    /// "Flipper", "Front armour", "Rear left wheel".
    var label: String
    /// 0 to 1 now.
    var condition: Double
    /// 0 to 1 when the match started.
    var startCondition: Double
    var destroyed: Bool { condition <= 0 }
    var percent: Int { Int((condition * 100).rounded()) }
    var id: String { label }
}

/// Brief v5 section 5, decoded from FightResult v2 by agent A (`ProgressionEngine.matchReport`).
struct MatchReport: Equatable {
    enum Result: String { case win, loss, draw }

    var result: Result
    /// `ko`, `out_of_arena`, `judges`, `component_kill`, `timeout`, `forfeit`.
    var outcome: String
    var durationSeconds: Double
    var hitsLanded: Int
    var hitsTaken: Int
    var parts: [PartCondition]
    /// Names of parts destroyed or disabled this match (from the arena's `parts_lost`).
    var partsLost: [String]
    var botName: String
    var opponentName: String
    /// The scrap the arena tallied, banked or not. Nil when the arena sent no breakdown.
    var scrap: ScrapBreakdown?

    var isWin: Bool { result == .win }
    /// "2:14"
    var durationText: String {
        let whole = Int(durationSeconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

/// `scrap_breakdown[bot]` from the arena. Zero lines are printed as zero, not hidden.
struct ScrapBreakdown: Codable, Equatable {
    var base: Int = 0
    var damage: Int = 0
    var survivor: Int = 0
    var flawless: Int = 0
    var total: Int { base + damage + survivor + flawless }
    var isFlawless: Bool { flawless > 0 }
}

// MARK: - Rewards

/// Brief v5 section 6. Only ever built for a win.
struct Rewards: Equatable {
    var scrap: ScrapBreakdown
    var levelPoints: Int
    var levelBefore: LevelState
    var levelAfter: LevelState
    var series: SeriesProgress
    /// Part ids whose Level was reached by this win, in ladder order.
    var newlyUnlocked: [String]
    /// Paint job ids reached by this win.
    var newPaintJobs: [String]
    /// True when this win finished the Series.
    var finishedSeries: Bool
    /// True when this win finished the campaign.
    var finishedCampaign: Bool
    /// True when the next Series is behind the full-game wall.
    var hitTheWall: Bool
    var levelsGained: Int { levelAfter.level - levelBefore.level }
}

// MARK: - The shop

struct ShopEntry: Equatable, Identifiable {
    enum Category: String, CaseIterable { case chassis, drive, weapon, utility, material }
    enum Availability: Equatable { case owned, buyable, needsLevel(Int), behindWall, tooPoor }

    var id: String
    var name: String
    var category: Category
    var weight: Double
    var price: Int
    var levelRequired: Int
    var blurb: String
    var availability: Availability

    var isOwned: Bool { availability == .owned }
}

// MARK: - Paint jobs

struct PaintJob: Equatable, Identifiable {
    var id: String
    var name: String
    var level: Int
    var unlocked: Bool
}
