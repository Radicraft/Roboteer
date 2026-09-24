//
//  CareerCatalogue.swift
//  The `career`, `rivals`, `bosses`, `economy` and `progression` blocks of `Shared/parts.json`,
//  read once in the
//  order they were written. Same file, same bytes, same parser as `Catalogue`: Godot reads it from
//  `res://data/parts.json` (copied by `scripts/export-pck.sh`) and Swift reads it from the bundle.
//
//  Every fee, purse, capacity, price factor, rival and boss in the game is in that file. Nothing in
//  this type invents a number; the only thing it adds is a fallback so a missing block leaves the
//  app running rather than crashing.
//

import Foundation

struct CareerCatalogue {

    // MARK: - Types

    struct TierEntry: Identifiable, Equatable {
        let id: String
        let name: String
        let index: Int
        let entryFee: Int
        let purse: Int
        let finalMultiplier: Int
        let garageCapacity: Int
        /// Arena ids, in order. Championship alternates two; every other tier has one.
        let arenas: [String]
        let rounds: Int
        /// Low and high of the filler bots' strength at this tier, as a fraction of the budget.
        let powerBand: (low: Double, high: Double)
        let free: Bool
        /// The drip, in the order it is handed out, one per win with the remainder on the last win.
        let blueprints: [String]

        var tier: CareerTier { CareerTier.named(id) }

        /// The arena this round is fought in. Championship alternates Furnace and Crush.
        func arena(round: Int) -> String {
            guard !arenas.isEmpty else { return "yard" }
            return arenas[((round % arenas.count) + arenas.count) % arenas.count]
        }

        static func == (lhs: TierEntry, rhs: TierEntry) -> Bool { lhs.id == rhs.id }
    }

    /// One part swap in a rival's upgrade path. `slot` is `chassis`, `drive`, `weapon`,
    /// `utility_1`, `utility_2`, or `armour_front` / `armour_sides` / `armour_rear` / `armour_top`.
    struct Swap: Equatable {
        let slot: String
        let part: String?
        let material: String?
        let thickness: Int?
    }

    struct RivalEntry: Identifiable, Equatable {
        let id: String
        let name: String
        let roboteer: String
        let liveryHex: String
        let fromTier: CareerTier
        let personality: String
        /// G3's `temperament` key (brief v4 section 4): brawler, technician, bully, opportunist or
        /// showboat. Empty until that key reaches `Shared/parts.json`, and
        /// `CareerEngine.temperament(for:seasonSeed:)` derives one deterministically meanwhile, so
        /// a rival keeps the same temperament for life either way.
        let temperament: String
        let spec: BuildSpec
        /// Three lines: never met, they beat you last, you beat them last.
        let grudgeLines: [String]
        /// Tier raw value to the swaps applied on reaching it.
        let upgrades: [String: [Swap]]

        static func == (lhs: RivalEntry, rhs: RivalEntry) -> Bool { lhs.id == rhs.id }
    }

    struct BossEntry: Identifiable, Equatable {
        let id: String
        let name: String
        let signature: String
        let aiMode: String
        let blurb: String
        let liveryHex: String
        let spec: BuildSpec

        static func == (lhs: BossEntry, rhs: BossEntry) -> Bool { lhs.id == rhs.id }
    }

    struct Economy: Equatable {
        let priceFactor: [String: Double]
        let writeOffThreshold: Double
        let scrapForParts: Double

        func factor(_ category: String) -> Double { priceFactor[category] ?? 0 }
    }

    // MARK: - Progression (wave P, brief v5)

    /// One Series: four matches in a fixed order, its own arenas, its own scrap rates
    /// (`progression.series[n]` of `Shared/parts.json`). The id is the circuit id the arena, the
    /// rivals, the house bots and the AI all key on, so nothing else had to be renamed; on screen
    /// a Series is only ever "Series 1" and its name.
    struct SeriesEntry: Identifiable, Equatable {

        /// One match on the strip: a rival id, or a filler drawn from the career seed.
        struct MatchEntry: Equatable {
            let opponent: String
            let isFinal: Bool
            var isFiller: Bool { opponent.isEmpty || opponent == "filler" }
        }

        let id: String
        let name: String
        let index: Int
        /// 1 to 5, what the player reads.
        let number: Int
        /// Arena ids, in order. A Series with two alternates them by match.
        let arenas: [String]
        let winPoints: Int
        let scrap: ScrapRules
        let matches: [MatchEntry]

        var tier: CareerTier { CareerTier.named(id) }

        /// The arena this match is fought in. Two arenas alternate, one is every match.
        func arena(matchIndex: Int) -> String {
            guard !arenas.isEmpty else { return "yard" }
            return arenas[((matchIndex % arenas.count) + arenas.count) % arenas.count]
        }

        func match(_ index: Int) -> MatchEntry? {
            matches.indices.contains(index) ? matches[index] : nil
        }

        static func == (lhs: SeriesEntry, rhs: SeriesEntry) -> Bool { lhs.id == rhs.id }
    }

    /// One free cosmetic milestone (`progression.paint_jobs`).
    struct PaintJobEntry: Identifiable, Equatable {
        let id: String
        let name: String
        let level: Int
    }

    /// The whole `progression` block. Every number brief v5 turns on is in here and nowhere else.
    struct Progression: Equatable {
        let pointsPerLevel: Int
        let levelCap: Int
        /// The highest `level_required` the free game may buy.
        let freeLevelCap: Int
        /// What a flawless win adds to the Level points, as a fraction.
        let flawlessPointsBonus: Double
        /// What a replay of an already won match pays, as a fraction of scrap and points.
        let replayScale: Double
        let series: [SeriesEntry]
        let levelRequired: [String: Int]
        let displayNames: [String: String]
        let paintJobs: [PaintJobEntry]
        /// Wave B (docs/wave-b-progression-notes.md): the round and the opener, the medals, the
        /// title defence, the daily exhibition and the free taster. Every one has a default, so a
        /// catalogue without these blocks still plays exactly as it did.
        var round: RoundRules = RoundRules()
        var medals: MedalRules = MedalRules()
        var defence: DefenceRules = DefenceRules()
        var daily: DailyRules = DailyRules()
        var taster: TasterRules = TasterRules()

        /// True when the block is missing from the catalogue, which is the one case every reader
        /// falls back for rather than showing a zero.
        var isEmpty: Bool { series.isEmpty || levelRequired.isEmpty }

        func series(_ index: Int) -> SeriesEntry? {
            self.series.indices.contains(index) ? self.series[index] : nil
        }

        func series(_ tier: CareerTier) -> SeriesEntry? {
            self.series.first { $0.id == tier.rawValue }
        }

        static let empty = Progression(
            pointsPerLevel: 100, levelCap: 100, freeLevelCap: 33,
            flawlessPointsBonus: 0.25, replayScale: 0.5,
            series: [], levelRequired: [:], displayNames: [:], paintJobs: []
        )
    }

    // MARK: - Wave B blocks (owner decisions 3, 8, 9 and 13, docs/aaa/decisions-2026-09-24.md)

    /// `progression.round` and `progression.opener`: how long a career match runs and when the
    /// house bot comes out. The opener is the very first career match only (decision 9).
    struct RoundRules: Equatable {
        var durationS = 180
        var endgameAtS = 120
        var openerDurationS = 120
        var openerEndgameAtS = 80
    }

    struct MedalKindEntry: Equatable {
        let id: String
        let name: String
        let line: String
    }

    /// `progression.medals` (decision 3).
    struct MedalRules: Equatable {
        var survivorMin = 0.7
        /// What a replay that earns a medal for the first time pays, as a fraction of the match.
        var newMedalScale = 1.0
        var knockoutOutcomes: [String] = ["ko", "out_of_arena", "component_kill"]
        var kinds: [MedalKindEntry] = [
            MedalKindEntry(id: "win", name: "Win", line: "Beat them."),
            MedalKindEntry(id: "survivor", name: "Survivor", line: "Win with more than 70 % of your machine left."),
            MedalKindEntry(id: "finisher", name: "Knockout or flawless", line: "Win before the bell, or without losing a part.")
        ]
    }

    /// `progression.defence` (decision 8): the title defence after the campaign.
    struct DefenceRules: Equatable {
        var challengers: [String] = ["penny_dread", "scuttle", "clatterbox", "hob_nail",
                                     "cold_snap", "brass_neck", "marrow", "tollgate"]
        var arenas: [String] = ["yard", "grinder", "drop_zone", "furnace", "crush", "coliseum"]
        var payScale = 0.5
        var houseSpeedStep = 0.05
        var houseSpeedMax = 1.25
    }

    struct TwistEntry: Equatable {
        let id: String
        let name: String
        let line: String
    }

    /// `progression.daily` (decision 8): one seeded exhibition per UTC day.
    struct DailyRules: Equatable {
        var leaderboard = "daily_exhibition"
        var daysKept = 7
        var scoreWin = 1000
        var scoreDamage = 600
        var scoreHealth = 400
        var scoreTime = 3
        var scoreHits = 10
        var arenas: [String] = ["yard", "grinder", "drop_zone", "furnace", "crush", "coliseum"]
        var twists: [TwistEntry] = [TwistEntry(id: "standard", name: "Straight fight",
                                               line: "Three minutes, house bot in its corner, nothing added.")]
    }

    /// `progression.taster` (decision 13): what a free game may try of the locked modes.
    struct TasterRules: Equatable {
        var events = 1
        var ladderFights = 1
    }

    // MARK: - Contents

    let startingUnlocks: [String]
    let tierOrder: [String]
    let tiers: [TierEntry]
    let rivals: [RivalEntry]
    let bosses: [BossEntry]
    let economy: Economy
    let fillerNames: [String]
    let fillerRoboteers: [String]
    /// Wave P: the `progression` block. `ProgressionEngine` is the only thing that reads it.
    let progression: Progression

    // MARK: - Lookups

    func tier(_ id: String) -> TierEntry? { tiers.first { $0.id == id } }
    func tier(_ tier: CareerTier) -> TierEntry? { self.tier(tier.rawValue) }
    func rival(_ id: String) -> RivalEntry? { rivals.first { $0.id == id } }
    func boss(_ id: String) -> BossEntry? { bosses.first { $0.id == id } }
    func series(_ index: Int) -> SeriesEntry? { progression.series(index) }
    func series(_ tier: CareerTier) -> SeriesEntry? { progression.series(tier) }

    /// Every rival who is in the circuit by this tier.
    func rivals(upTo tier: CareerTier) -> [RivalEntry] {
        rivals.filter { $0.fromTier.index <= tier.index }
    }

    /// Everything the player holds after taking every tier up to and including this one.
    func unlocks(upTo tier: CareerTier) -> Set<String> {
        var held = Set(startingUnlocks)
        for entry in tiers where entry.index <= tier.index {
            held.formUnion(entry.blueprints)
        }
        return held
    }

    /// Which tier earns a part, for the "Earned at Regional" line on a locked picker row.
    func tierThatUnlocks(_ partID: String) -> TierEntry? {
        tiers.first { $0.blueprints.contains(partID) }
    }

    /// The drip this tier has handed out after so many wins. The last win of a tier hands over
    /// everything that is left, so a tier's drip is always complete when the tier is.
    func drip(tier: CareerTier, afterWins wins: Int) -> [String] {
        guard let entry = self.tier(tier) else { return [] }
        if wins >= entry.rounds { return entry.blueprints }
        return Array(entry.blueprints.prefix(max(0, wins)))
    }

    // MARK: - Loading

    static let shared: CareerCatalogue = load()

    static func load() -> CareerCatalogue {
        guard let url = Bundle.main.url(forResource: "parts", withExtension: "json"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let root = JSONValue.parse(text) else {
            assertionFailure("parts.json is missing from the bundle or did not parse")
            return .empty
        }
        return CareerCatalogue(root: root)
    }

    static let empty = CareerCatalogue(
        startingUnlocks: [], tierOrder: [], tiers: [], rivals: [], bosses: [],
        economy: Economy(priceFactor: [:], writeOffThreshold: 0.7, scrapForParts: 0.4),
        fillerNames: [], fillerRoboteers: [], progression: .empty
    )

    private init(
        startingUnlocks: [String], tierOrder: [String], tiers: [TierEntry],
        rivals: [RivalEntry], bosses: [BossEntry], economy: Economy,
        fillerNames: [String], fillerRoboteers: [String], progression: Progression
    ) {
        self.startingUnlocks = startingUnlocks
        self.tierOrder = tierOrder
        self.tiers = tiers
        self.rivals = rivals
        self.bosses = bosses
        self.economy = economy
        self.fillerNames = fillerNames
        self.fillerRoboteers = fillerRoboteers
        self.progression = progression
    }

    private init(root: JSONValue) {
        let career = root["career"]
        startingUnlocks = career?["starting_unlocks"]?.stringItems ?? []
        tierOrder = career?["tier_order"]?.stringItems ?? CareerTier.allCases.map(\.rawValue)
        fillerNames = career?["filler_names"]?.stringItems ?? []
        fillerRoboteers = career?["filler_roboteers"]?.stringItems ?? []

        tiers = (career?["tiers"]?.members ?? []).map { member in
            let value = member.value
            let band = (value["power_band"]?.items ?? []).compactMap { $0.doubleValue }
            return TierEntry(
                id: member.key,
                name: value["name"]?.stringValue ?? member.key.capitalizedFirst,
                index: value["index"]?.intValue ?? 0,
                entryFee: value["entry_fee"]?.intValue ?? 0,
                purse: value["purse"]?.intValue ?? 0,
                finalMultiplier: value["final_multiplier"]?.intValue ?? 1,
                garageCapacity: value["garage_capacity"]?.intValue ?? 1,
                arenas: value["arenas"]?.stringItems ?? ["yard"],
                rounds: value["rounds"]?.intValue ?? 3,
                powerBand: (band.first ?? 0.6, band.count > 1 ? band[1] : 0.8),
                free: value["free"]?.boolValue ?? false,
                blueprints: value["blueprints"]?.stringItems ?? []
            )
        }

        rivals = (root["rivals"]?.members ?? []).map { member in
            let value = member.value
            var upgrades: [String: [Swap]] = [:]
            for tierMember in (value["upgrades"]?.members ?? []) {
                upgrades[tierMember.key] = tierMember.value.items.map { CareerCatalogue.swap($0) }
            }
            return RivalEntry(
                id: member.key,
                name: value["name"]?.stringValue ?? member.key,
                roboteer: value["roboteer"]?.stringValue ?? "",
                liveryHex: value["livery"]?.stringValue ?? "#3358a0",
                fromTier: CareerTier.named(value["from_tier"]?.stringValue ?? "scrapyard"),
                personality: value["personality"]?.stringValue ?? "",
                temperament: value["temperament"]?.stringValue ?? "",
                spec: CareerCatalogue.spec(
                    value["build"],
                    name: value["name"]?.stringValue ?? member.key,
                    livery: value["livery"]?.stringValue ?? "#3358a0"
                ),
                grudgeLines: value["grudge_lines"]?.stringItems ?? [],
                upgrades: upgrades
            )
        }

        bosses = (root["bosses"]?.members ?? []).map { member in
            let value = member.value
            return BossEntry(
                id: member.key,
                name: value["name"]?.stringValue ?? member.key.uppercased(),
                signature: value["signature"]?.stringValue ?? "",
                aiMode: value["ai_mode"]?.stringValue ?? "normal",
                blurb: value["blurb"]?.stringValue ?? "",
                liveryHex: value["livery"]?.stringValue ?? "#4a5058",
                spec: CareerCatalogue.spec(
                    value["build"],
                    name: value["name"]?.stringValue ?? member.key.uppercased(),
                    livery: value["livery"]?.stringValue ?? "#4a5058"
                )
            )
        }

        let money = root["economy"]
        var factors: [String: Double] = [:]
        for member in (money?["price_factor"]?.members ?? []) {
            factors[member.key] = member.value.doubleValue ?? 0
        }
        economy = Economy(
            priceFactor: factors,
            writeOffThreshold: money?["write_off_threshold"]?.doubleValue ?? 0.7,
            scrapForParts: money?["scrap_for_parts"]?.doubleValue ?? 0.4
        )

        progression = CareerCatalogue.readProgression(root["progression"])
    }

    /// The `progression` block, read as tolerantly as everything else: a missing key is a default,
    /// a missing block is `Progression.empty`, and `ProgressionEngine` falls back to the career
    /// blocks when it is empty rather than printing zeroes.
    private static func readProgression(_ value: JSONValue?) -> Progression {
        guard let value else { return .empty }
        let defaults = Progression.empty

        let series = (value["series"]?.items ?? []).enumerated().map { pair -> SeriesEntry in
            let entry = pair.element
            let id = entry["id"]?.stringValue ?? CareerTier.allCases[min(pair.offset, 4)].rawValue
            let money = entry["scrap"]
            return SeriesEntry(
                id: id,
                name: entry["name"]?.stringValue ?? id.capitalizedFirst,
                index: entry["index"]?.intValue ?? pair.offset,
                number: entry["number"]?.intValue ?? (pair.offset + 1),
                arenas: entry["arenas"]?.stringItems ?? ["yard"],
                winPoints: entry["win_points"]?.intValue ?? 0,
                scrap: ScrapRules(
                    base: money?["base"]?.intValue ?? 0,
                    damageFull: money?["damage_full"]?.intValue ?? 0,
                    survivor: money?["survivor"]?.intValue ?? 0,
                    survivorMin: money?["survivor_min"]?.doubleValue ?? 0.7,
                    flawless: money?["flawless"]?.intValue ?? 0
                ),
                matches: (entry["matches"]?.items ?? []).map { match in
                    SeriesEntry.MatchEntry(
                        opponent: match["opponent"]?.stringValue ?? "filler",
                        isFinal: match["final"]?.boolValue ?? false
                    )
                }
            )
        }

        var levels: [String: Int] = [:]
        for member in (value["level_required"]?.members ?? []) {
            levels[member.key] = member.value.intValue ?? 1
        }
        var names: [String: String] = [:]
        for member in (value["display_names"]?.members ?? []) {
            guard let text = member.value.stringValue, !text.isEmpty else { continue }
            names[member.key] = text
        }
        let paint = (value["paint_jobs"]?.items ?? []).enumerated().map { pair in
            PaintJobEntry(
                id: pair.element["id"]?.stringValue ?? "paint_\(pair.offset)",
                name: pair.element["name"]?.stringValue ?? "Paint job",
                level: pair.element["level"]?.intValue ?? 1
            )
        }

        var round = RoundRules()
        if let block = value["round"] {
            round.durationS = block["duration_s"]?.intValue ?? round.durationS
            round.endgameAtS = block["endgame_at_s"]?.intValue ?? round.endgameAtS
        }
        if let block = value["opener"] {
            round.openerDurationS = block["duration_s"]?.intValue ?? round.openerDurationS
            round.openerEndgameAtS = block["endgame_at_s"]?.intValue ?? round.openerEndgameAtS
        }

        var medals = MedalRules()
        if let block = value["medals"] {
            medals.survivorMin = block["survivor_min"]?.doubleValue ?? medals.survivorMin
            medals.newMedalScale = block["new_medal_scale"]?.doubleValue ?? medals.newMedalScale
            if let outcomes = block["knockout_outcomes"]?.stringItems, !outcomes.isEmpty {
                medals.knockoutOutcomes = outcomes
            }
            let kinds = (block["kinds"]?.items ?? []).compactMap { item -> MedalKindEntry? in
                guard let id = item["id"]?.stringValue else { return nil }
                return MedalKindEntry(id: id, name: item["name"]?.stringValue ?? id.capitalizedFirst,
                                      line: item["line"]?.stringValue ?? "")
            }
            if !kinds.isEmpty { medals.kinds = kinds }
        }

        var defence = DefenceRules()
        if let block = value["defence"] {
            if let list = block["challengers"]?.stringItems, !list.isEmpty { defence.challengers = list }
            if let list = block["arenas"]?.stringItems, !list.isEmpty { defence.arenas = list }
            defence.payScale = block["pay_scale"]?.doubleValue ?? defence.payScale
            defence.houseSpeedStep = block["house_speed_step"]?.doubleValue ?? defence.houseSpeedStep
            defence.houseSpeedMax = block["house_speed_max"]?.doubleValue ?? defence.houseSpeedMax
        }

        var daily = DailyRules()
        if let block = value["daily"] {
            daily.leaderboard = block["leaderboard"]?.stringValue ?? daily.leaderboard
            daily.daysKept = max(1, block["days_kept"]?.intValue ?? daily.daysKept)
            let score = block["score"]
            daily.scoreWin = score?["win"]?.intValue ?? daily.scoreWin
            daily.scoreDamage = score?["damage"]?.intValue ?? daily.scoreDamage
            daily.scoreHealth = score?["health"]?.intValue ?? daily.scoreHealth
            daily.scoreTime = score?["time"]?.intValue ?? daily.scoreTime
            daily.scoreHits = score?["hits"]?.intValue ?? daily.scoreHits
            if let list = block["arenas"]?.stringItems, !list.isEmpty { daily.arenas = list }
            let twists = (block["twists"]?.items ?? []).compactMap { item -> TwistEntry? in
                guard let id = item["id"]?.stringValue else { return nil }
                return TwistEntry(id: id, name: item["name"]?.stringValue ?? id.capitalizedFirst,
                                  line: item["line"]?.stringValue ?? "")
            }
            if !twists.isEmpty { daily.twists = twists }
        }

        var taster = TasterRules()
        if let block = value["taster"] {
            taster.events = max(0, block["events"]?.intValue ?? taster.events)
            taster.ladderFights = max(0, block["ladder_fights"]?.intValue ?? taster.ladderFights)
        }

        return Progression(
            pointsPerLevel: max(1, value["points_per_level"]?.intValue ?? defaults.pointsPerLevel),
            levelCap: max(1, value["level_cap"]?.intValue ?? defaults.levelCap),
            freeLevelCap: value["free_level_cap"]?.intValue ?? defaults.freeLevelCap,
            flawlessPointsBonus: value["flawless_points_bonus"]?.doubleValue ?? defaults.flawlessPointsBonus,
            replayScale: value["replay_scale"]?.doubleValue ?? defaults.replayScale,
            series: series.sorted { $0.index < $1.index },
            levelRequired: levels,
            displayNames: names,
            paintJobs: paint.sorted { $0.level < $1.level },
            round: round,
            medals: medals,
            defence: defence,
            daily: daily,
            taster: taster
        )
    }

    private static func swap(_ value: JSONValue) -> Swap {
        Swap(
            slot: value["slot"]?.stringValue ?? "",
            part: value["part"]?.stringValue,
            material: value["material"]?.stringValue,
            thickness: value["thickness"]?.intValue
        )
    }

    /// A `build` block from the catalogue into the same `BuildSpec` the builder uses.
    private static func spec(_ value: JSONValue?, name: String, livery: String) -> BuildSpec {
        var armour: [String: ArmourFaceSpec] = [:]
        for member in (value?["armour"]?.members ?? []) {
            armour[member.key] = ArmourFaceSpec(
                material: member.value["material"]?.stringValue ?? "hdpe",
                thickness: member.value["thickness"]?.intValue ?? 1
            )
        }
        return BuildSpec(
            name: name,
            chassis: value?["chassis"]?.stringValue ?? "box",
            drive: value?["drive"]?.stringValue ?? "4wd",
            weapon: value?["weapon"]?.stringValue ?? "ram",
            utilities: value?["utility"]?.stringItems ?? ["srimech"],
            armour: armour,
            liveryHex: livery
        )
    }
}
