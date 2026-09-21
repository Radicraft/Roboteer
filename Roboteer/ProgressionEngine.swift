//
//  ProgressionEngine.swift
//  The career progression of brief v5 (docs/brief-v5-progression.md), as pure functions: Series,
//  Level, Scrap, the shop and the post-match report. Nothing here touches SwiftData, SwiftUI or
//  the arena, which is what lets `-careerSelfTest` script a whole twenty match campaign through it
//  at launch and what lets the same code compile as a command line binary on a Mac.
//
//  Every number comes from the `progression` block of `Shared/parts.json` by way of
//  `CareerCatalogue.shared.progression`, and every price from `economy.price_factor`. Nothing in
//  this file invents a number; the only thing it adds is a fallback so a missing block leaves the
//  app running rather than printing zeroes.
//
//  Signatures are the wave P contract (docs/wave-p-contracts.md). Parameters added since the stub
//  all carry defaults, so the screens B1 and B2 built against the stub keep compiling.
//

import Foundation

enum ProgressionEngine {

    static var progression: CareerCatalogue.Progression { CareerCatalogue.shared.progression }
    static var catalogue: CareerCatalogue { CareerCatalogue.shared }
    static var parts: Catalogue { Catalogue.shared }

    /// `bots[i].id` of the player's machine, which is what every result block is keyed by.
    /// `CareerFightConfig.playerID` is the same string; it lives in a SwiftUI file this engine
    /// cannot see, so the self test asserts the two agree rather than one importing the other.
    static let playerID = "player-1"

    /// The scrap a fresh career opens with (brief v5: the starting machine is owned, this is the
    /// float for the first repair). `CareerStore` reads it from here so there is one copy.
    static let openingScrap = 300

    // MARK: - The catalogue

    /// The Level a part needs before it can be bought. Level 1 for anything the ladder does not
    /// name, so a part added to the catalogue without a ladder entry is buyable rather than
    /// invisible (the self test reports any that are missing).
    static func levelRequired(_ partID: String) -> Int {
        progression.levelRequired[partID] ?? 1
    }

    /// "Ram plow" for `ram`; the catalogue name for everything else (`progression.display_names`).
    static func displayName(_ partID: String) -> String {
        if let name = progression.displayNames[partID] { return name }
        return CareerEngine.partName(partID)
    }

    /// What a part costs in the shop: `economy.price_factor` for its kind times its weight, the
    /// same formula the repair bill and the build value have always used.
    ///
    /// An armour material is the one thing that is not bought by the part, because a material is
    /// fitted to any face at any thickness once it is owned. Its shop price is therefore one
    /// reference plate: the `armour` factor times `kg_per_unit_area` times the front face's area
    /// times two units, which is what the starting machine's front plate actually is.
    static func price(_ partID: String) -> Int {
        let money = catalogue.economy
        if let part = parts.chassis(partID) { return rounded(part.weight * money.factor("chassis")) }
        if let part = parts.drive(partID) { return rounded(part.weight * money.factor("drive")) }
        if let part = parts.weapon(partID) { return rounded(part.weight * money.factor("weapon")) }
        if let part = parts.utility(partID) { return rounded(part.weight * money.factor("utility")) }
        if let part = parts.material(partID) {
            return rounded(referencePlateWeight(part) * money.factor("armour"))
        }
        return 0
    }

    /// The plate a material is priced and weighed by in the shop: the front face at two units.
    static func referencePlateWeight(_ material: Catalogue.Material) -> Double {
        let area = parts.face("front")?.area ?? 1
        return material.kgPerUnitArea * area * 2
    }

    /// What the shop row prints as the weight. A part's own weight, and for a material the same
    /// reference plate its price is worked out from, so the two numbers agree on the row.
    static func weight(_ partID: String) -> Double {
        if let part = parts.chassis(partID) { return part.weight }
        if let part = parts.drive(partID) { return part.weight }
        if let part = parts.weapon(partID) { return part.weight }
        if let part = parts.utility(partID) { return part.weight }
        if let part = parts.material(partID) { return referencePlateWeight(part) }
        return 0
    }

    static func category(_ partID: String) -> ShopEntry.Category? {
        if parts.chassis(partID) != nil { return .chassis }
        if parts.drive(partID) != nil { return .drive }
        if parts.weapon(partID) != nil { return .weapon }
        if parts.utility(partID) != nil { return .utility }
        if parts.material(partID) != nil { return .material }
        return nil
    }

    /// The catalogue's own sentence about a part. A material has no blurb of its own, so it gets
    /// the summary the builder's picker prints.
    static func blurb(_ partID: String) -> String {
        if let part = parts.chassis(partID) { return part.blurb }
        if let part = parts.drive(partID) { return part.blurb }
        if let part = parts.weapon(partID) { return part.blurb }
        if let part = parts.utility(partID) { return part.blurb }
        if let part = parts.material(partID) { return part.summary }
        return ""
    }

    /// `rules.scrap` for a Series (brief v5 section 3). A replay pays `replay_scale` of it, which
    /// is why the scale is applied here rather than after the fight: the arena tallies the live
    /// bug from these numbers, so a replay's bug has to show the replay's money.
    static func scrapRules(seriesIndex: Int, replay: Bool = false) -> ScrapRules {
        guard let series = progression.series(seriesIndex) else { return ScrapRules() }
        guard replay else { return series.scrap }
        let scale = progression.replayScale
        var rules = series.scrap
        rules.base = rounded(Double(rules.base) * scale)
        rules.damageFull = rounded(Double(rules.damageFull) * scale)
        rules.survivor = rounded(Double(rules.survivor) * scale)
        rules.flawless = rounded(Double(rules.flawless) * scale)
        return rules
    }

    /// What a win pays into the Level bar. A flawless win adds `flawless_points_bonus`; a replay
    /// of an already won match pays `replay_scale`.
    static func winPoints(seriesIndex: Int, flawless: Bool, replay: Bool) -> Int {
        guard let series = progression.series(seriesIndex) else { return 0 }
        var points = Double(series.winPoints)
        if flawless { points *= 1 + progression.flawlessPointsBonus }
        if replay { points *= progression.replayScale }
        return rounded(points)
    }

    /// "Scrapyard". The Series' own name from the catalogue.
    static func seriesName(_ seriesIndex: Int) -> String {
        if let series = progression.series(seriesIndex) { return series.name }
        let all = CareerTier.allCases
        return all[min(max(0, seriesIndex), all.count - 1)].title
    }

    /// "Series 2: Regional", the one way a Series is ever titled on screen.
    static func seriesLine(_ seriesIndex: Int) -> String {
        "Series \(seriesIndex + 1): \(seriesName(seriesIndex))"
    }

    /// The Level a player is at after winning every match up to and including this Series with no
    /// flawless wins. Series 5's answer is the Level cap, which is the ladder's whole promise.
    static func seriesLevelCeiling(_ seriesIndex: Int) -> Int {
        var points = 0
        for index in 0...max(0, seriesIndex) {
            guard let series = progression.series(index) else { continue }
            points += series.winPoints * SeriesProgress.matchesPerSeries
        }
        return level(points: min(points, maxPoints)).level
    }

    // MARK: - Level

    static func level(points: Int) -> LevelState {
        LevelState(
            points: max(0, min(points, maxPoints)),
            pointsPerLevel: progression.pointsPerLevel,
            cap: progression.levelCap
        )
    }

    /// The points the bar holds when it is full: one Level short of the cap's worth, so Level 100
    /// is exactly 9,900 points with the shipped numbers.
    static var maxPoints: Int {
        max(0, progression.levelCap - 1) * progression.pointsPerLevel
    }

    /// The points a Level starts at.
    static func points(forLevel level: Int) -> Int {
        max(0, min(level, progression.levelCap) - 1) * progression.pointsPerLevel
    }

    /// Part ids whose Level is reached by climbing from one Level to another, in ladder order.
    static func newlyUnlocked(from: Int, to: Int) -> [String] {
        guard to > from else { return [] }
        let held = Set(parts.allPartIDs)
        return progression.levelRequired
            .filter { $0.value > from && $0.value <= to && held.contains($0.key) }
            .sorted { ($0.value, $0.key) < ($1.value, $1.key) }
            .map(\.key)
    }

    /// Paint job ids reached by climbing from one Level to another.
    static func newPaintJobs(from: Int, to: Int) -> [String] {
        guard to > from else { return [] }
        return progression.paintJobs.filter { $0.level > from && $0.level <= to }.map(\.id)
    }

    // MARK: - The next match

    /// The rival the next match is against, or empty for a filler. The store needs this before it
    /// can fetch the `RivalRecord` that `nextMatch` wants, so it is on its own.
    static func opponentRivalID(state: CareerState) -> String {
        let (seriesIndex, matchIndex) = pending(state)
        guard let entry = progression.series(seriesIndex)?.match(matchIndex), !entry.isFiller,
              catalogue.rival(entry.opponent) != nil else { return "" }
        return entry.opponent
    }

    /// Which match is on duty: the replay if one is running, otherwise the campaign's own.
    static func pending(_ state: CareerState) -> (seriesIndex: Int, matchIndex: Int) {
        state.isReplaying
            ? (state.replaySeriesIndex, state.replayMatchIndex)
            : (state.seriesIndex, state.matchIndex)
    }

    /// Everything the next-match card prints and everything the fight config needs, in one place,
    /// so the card, the scouting report and the arena cannot disagree about who is on duty, where,
    /// or what a win pays. Nil when the Series is finished and there is nowhere to go.
    static func nextMatch(state: CareerState, playerBot: BotBuild? = nil, record: RivalRecord? = nil) -> NextMatch? {
        let replaying = state.isReplaying
        let (seriesIndex, matchIndex) = pending(state)
        guard let series = progression.series(seriesIndex),
              let entry = series.match(matchIndex) else { return nil }

        let tier = series.tier
        let arena = series.arena(matchIndex: matchIndex)
        let house = CareerEngine.houseBot(tier: tier, arena: arena)
        let opponent = self.opponent(seriesIndex: seriesIndex, matchIndex: matchIndex,
                                     careerSeed: state.currentSeasonSeed)
        let botName = playerBot?.name ?? "your machine"
        let repairs = playerBot.map {
            CareerEngine.repairBill(for: $0.spec, damage: $0.currentDamage).total
        } ?? 0

        return NextMatch(
            tier: tier,
            seriesIndex: seriesIndex,
            matchIndex: matchIndex,
            isFinal: entry.isFinal,
            isReplay: replaying,
            // A replay's attempt number is the career's fight count, so every replay of the same
            // match is fought on a different seed without disturbing the attempt count of the
            // match the player may be stuck on.
            attempts: replaying ? state.fightsPlayed : state.attempts,
            opponent: opponent,
            arena: arena,
            arenaName: parts.arena(arena)?.name ?? arena.capitalizedFirst,
            houseBotID: house.id,
            houseBotName: CareerEngine.houseBotName(house.id),
            houseBotSpeed: house.speed,
            houseBotLine: CareerEngine.houseBotLine(tier: tier, arena: arena),
            scoutingLine: scoutingLine(for: opponent),
            grudgeLine: grudgeLine(for: opponent, record: record, playerBotName: botName),
            aiSkill: CareerEngine.aiSkill(for: tier),
            temperament: CareerEngine.temperament(for: opponent, seasonSeed: state.currentSeasonSeed),
            scrapRules: scrapRules(seriesIndex: seriesIndex, replay: replaying),
            winPoints: winPoints(seriesIndex: seriesIndex, flawless: false, replay: replaying),
            repairsDue: repairs
        )
    }

    /// Who match `m` of Series `n` is against. A rival named in the catalogue, at that Series'
    /// strength, or a filler drawn from the career seed, the Series and the match, so the same
    /// career always fields the same machines in the same order.
    static func opponent(seriesIndex: Int, matchIndex: Int, careerSeed: Int) -> CareerEntrant {
        let all = CareerTier.allCases
        let tier = all[min(max(0, seriesIndex), all.count - 1)]
        let entry = progression.series(seriesIndex)?.match(matchIndex)

        if let entry, !entry.isFiller, let rival = catalogue.rival(entry.opponent) {
            return CareerEntrant(
                id: rival.id,
                name: rival.name,
                roboteer: rival.roboteer,
                liveryHex: rival.liveryHex,
                kind: .rival,
                spec: CareerEngine.rivalSpec(rival, at: tier),
                rivalID: rival.id
            )
        }

        var rng = SeededRandom(seed: careerSeed &* 7919 &+ seriesIndex &* 131 &+ matchIndex &* 17 &+ 1)
        let index = seriesIndex * SeriesProgress.matchesPerSeries + matchIndex
        return CareerEngine.fillerEntrant(index: index, tier: tier, rng: &rng)
    }

    /// What is known about this machine. A rival has a line in the catalogue; a filler is read off
    /// its own build, because nothing has ever been written about it.
    static func scoutingLine(for opponent: CareerEntrant) -> String {
        if let rival = catalogue.rival(opponent.rivalID), !rival.personality.isEmpty {
            return rival.personality
        }
        let weapon = displayName(opponent.spec.weapon)
        let chassis = displayName(opponent.spec.chassis)
        let weight = BuildRules.kilograms(BuildRules.totalWeight(opponent.spec))
        return "Nobody has written anything about this one. \(weapon) on a \(chassis), and \(weight)."
    }

    /// The grudge line, and only when there is history to have a grudge about.
    static func grudgeLine(for opponent: CareerEntrant, record: RivalRecord?, playerBotName: String) -> String {
        guard let record, record.rivalID == opponent.rivalID,
              record.hasMet, !record.grudgeLines.isEmpty else { return "" }
        return CareerEngine.grudgeLine(
            lines: record.grudgeLines,
            wins: record.winsVsPlayer,
            losses: record.lossesVsPlayer,
            theyWonLast: record.lastResultWasTheirs,
            playerName: record.roboteer,
            botName: playerBotName
        )
    }

    // MARK: - The Series strip

    /// The four slots of one Series, in order, for the Series screen and the campaign board.
    /// `logs` is the career's fight log; without it the won slots simply carry no note.
    static func seriesSlots(state: CareerState, seriesIndex: Int, logs: [FightLog] = []) -> [SeriesMatchSlot] {
        guard let series = progression.series(seriesIndex) else { return [] }
        let canReplay = replaysAvailable(state: state)

        return series.matches.indices.map { index -> SeriesMatchSlot in
            let entry = series.matches[index]
            let opponent = self.opponent(seriesIndex: seriesIndex, matchIndex: index,
                                         careerSeed: state.currentSeasonSeed)
            let won = isWon(state: state, seriesIndex: seriesIndex, matchIndex: index)
            let slotState: SeriesMatchSlot.State
            if won {
                slotState = canReplay ? .replayable : .won
            } else if seriesIndex == state.seriesIndex && index == state.matchIndex {
                slotState = .next
            } else {
                slotState = .locked
            }
            return SeriesMatchSlot(
                index: index,
                opponentName: opponent.name,
                opponentLiveryHex: opponent.liveryHex,
                isFinal: entry.isFinal,
                state: slotState,
                note: won ? note(for: logs, tier: series.id, round: index) : ""
            )
        }
    }

    /// Has this match been won. Everything in an earlier Series has, and everything before the
    /// match on duty in the current one.
    static func isWon(state: CareerState, seriesIndex: Int, matchIndex: Int) -> Bool {
        if seriesIndex < state.seriesIndex { return true }
        if seriesIndex > state.seriesIndex { return false }
        return matchIndex < state.matchIndex
    }

    /// Whether won matches may be replayed: after the campaign (brief v5 section 9.1), and also
    /// when the next Series is behind the full game wall, because otherwise a free player who has
    /// won the Series 2 final has no way left to earn scrap for the parts they have unlocked.
    static func replaysAvailable(state: CareerState, gates: Gates = Gates.snapshot) -> Bool {
        if state.campaignComplete { return true }
        guard state.seriesProgress.seriesComplete else { return false }
        guard let next = state.tier.next else { return true }
        return !gates.tierAvailable(next)
    }

    /// "Knockout at 34 s" for a match the log remembers, else an empty string.
    static func note(for logs: [FightLog], tier: String, round: Int) -> String {
        guard let log = logs.last(where: {
            $0.tierRaw == tier && $0.round == round && $0.didWin
                && $0.source == FightLog.Source.career
        }) else { return "" }
        return note(outcome: log.outcome, atSeconds: log.atSeconds)
    }

    /// The words a settled match is remembered by. Plain, and never an em dash.
    static func note(outcome: String, atSeconds: Double) -> String {
        let when = atSeconds > 0 ? " at \(Int(atSeconds.rounded())) s" : ""
        switch outcome {
        case "ko": return "Knockout\(when)"
        case "out_of_arena": return "Out of the arena\(when)"
        case "component_kill": return "Core destroyed\(when)"
        case "judges": return "Judges decision"
        case "timeout": return "Time ran out"
        case "forfeit": return "Forfeited"
        default: return outcome.replacingOccurrences(of: "_", with: " ").capitalizedFirst
        }
    }

    // MARK: - The match report

    /// Brief v5 section 5, decoded from FightResult v2. `resultJSON` is the result as it arrived;
    /// the v2 blocks are read straight out of it rather than off `FightResult`, because
    /// `FightResult.swift` belongs to the arena agent and this has to work both before and after
    /// their fields land. Every block is optional: a result without them still makes a report.
    ///
    /// A nil result is a forfeit loss: the fight never finished, so the machine comes home with
    /// the condition it went out in and nothing is banked.
    static func matchReport(
        result: FightResult?,
        spec: BuildSpec,
        startDamage: FightResult.BotDamage?,
        botName: String,
        opponentName: String,
        resultJSON: String = ""
    ) -> MatchReport {
        let extras = ResultExtras.parse(resultJSON)
        let start = extras.conditionStart[playerID] ?? startDamage

        guard let result else {
            return MatchReport(
                result: .loss, outcome: "forfeit", durationSeconds: 0,
                hitsLanded: 0, hitsTaken: 0,
                parts: partConditions(spec: spec, damage: start, start: start),
                partsLost: [], botName: botName, opponentName: opponentName, scrap: nil
            )
        }

        let kind: MatchReport.Result
        if result.outcome.winner == playerID {
            kind = .win
        } else if result.outcome.winner.isEmpty {
            kind = .draw
        } else {
            kind = .loss
        }

        let damage = result.damage[playerID]
        let conditions = partConditions(spec: spec, damage: damage, start: start)
        let hits = extras.hits[playerID]

        // What the arena says was lost, and failing that what the conditions show: a part at zero
        // that was not at zero when the match started.
        let lost: [String]
        if let listed = extras.partsLost[playerID], !listed.isEmpty {
            lost = listed.map { $0.label.isEmpty ? $0.part : $0.label }
        } else {
            lost = conditions.filter { $0.condition <= 0 && $0.startCondition > 0 }.map(\.label)
        }

        return MatchReport(
            result: kind,
            outcome: result.outcome.type,
            durationSeconds: result.durationSeconds,
            hitsLanded: hits?.landed ?? 0,
            hitsTaken: hits?.taken ?? 0,
            parts: conditions,
            partsLost: lost,
            botName: botName,
            opponentName: opponentName,
            scrap: extras.scrap[playerID]
        )
    }

    /// Every part of the machine that has a condition, labelled the way the repair bill labels it:
    /// the catalogue's own name for the weapon, the drive and the hull, "Front armour" for a
    /// plate, and a position for each wheel or track in the order the arena reports them (front
    /// before rear, left before right, which is `drive_base.gd`'s own order).
    ///
    /// Utilities are not in the list. They ride the hull and the arena reports no condition for
    /// them, so printing one would be inventing a number.
    static func partConditions(
        spec: BuildSpec,
        damage: FightResult.BotDamage?,
        start: FightResult.BotDamage?
    ) -> [PartCondition] {
        let drive = parts.drive(spec.drive)
        let wheelCount = damage?.wheels.count ?? start?.wheels.count ?? drive?.conditionCount ?? 4
        var out: [PartCondition] = []

        func add(_ label: String, _ now: Double?, _ before: Double?) {
            out.append(PartCondition(
                label: label,
                condition: clamp(now ?? 1),
                startCondition: clamp(before ?? 1)
            ))
        }

        add(displayName(spec.weapon), damage?.weapon, start?.weapon)
        add(displayName(spec.drive), damage?.drive, start?.drive)

        let labels = wheelLabels(count: wheelCount, isTracked: (drive?.tracks ?? 0) > 0)
        for index in 0..<max(0, wheelCount) {
            let label = index < labels.count ? labels[index] : "Wheel \(index + 1)"
            add(label, item(damage?.wheels, index), item(start?.wheels, index))
        }

        for face in parts.faces {
            add("\(face.name) armour", armour(damage, face.id), armour(start, face.id))
        }

        add(displayName(spec.chassis), damage?.core, start?.core)
        return out
    }

    /// "Front left wheel", in the order `drive_base.gd` builds them: front before middle before
    /// rear, left before right. Tracks report one condition per side.
    static func wheelLabels(count: Int, isTracked: Bool) -> [String] {
        if isTracked {
            return count == 2 ? ["Left track", "Right track"] : (0..<max(0, count)).map { "Track \($0 + 1)" }
        }
        switch count {
        case 2: return ["Left wheel", "Right wheel"]
        case 4: return ["Front left wheel", "Front right wheel", "Rear left wheel", "Rear right wheel"]
        case 6: return ["Front left wheel", "Front right wheel", "Middle left wheel",
                        "Middle right wheel", "Rear left wheel", "Rear right wheel"]
        default: return (0..<max(0, count)).map { "Wheel \($0 + 1)" }
        }
    }

    // MARK: - Settling a match

    /// Everything one settled match does to the career, worked out as a value so the self test can
    /// script a whole campaign through it and so `CareerStore` only has to write it down.
    struct Settled: Equatable {
        var result: MatchReport.Result = .loss
        /// What was banked. Every line is zero on anything but a win.
        var scrap: ScrapBreakdown = ScrapBreakdown()
        var levelPoints: Int = 0
        var pointsAfter: Int = 0
        var seriesIndex: Int = 0
        var matchIndex: Int = 0
        var attempts: Int = 0
        var campaignComplete: Bool = false
        var finishedSeries: Bool = false
        var finishedCampaign: Bool = false
        /// The Series final was won but the next Series is behind the full game wall, so the
        /// player stays where they are and can replay what they have won.
        var hitTheWall: Bool = false
        var newlyUnlocked: [String] = []
        var newPaintJobs: [String] = []
        /// Only ever built for a win (brief v5 section 6).
        var rewards: Rewards?

        var didWin: Bool { result == .win }
    }

    /// Brief v5 sections 2, 3, 6 and 9.1 in one pure function: bank the scrap and the points on a
    /// win, move the campaign on, bump the attempt count on anything else.
    static func settle(
        seriesIndex: Int,
        matchIndex: Int,
        attempts: Int,
        points: Int,
        paintSeen: [String] = [],
        result: MatchReport.Result,
        breakdown: ScrapBreakdown?,
        isReplay: Bool,
        campaignComplete: Bool,
        gates: Gates = Gates.snapshot
    ) -> Settled {
        var out = Settled()
        out.result = result
        out.seriesIndex = seriesIndex
        out.matchIndex = matchIndex
        out.attempts = attempts
        out.campaignComplete = campaignComplete
        out.pointsAfter = min(max(0, points), maxPoints)

        let all = CareerTier.allCases
        let tier = all[min(max(0, seriesIndex), all.count - 1)]

        guard result == .win else {
            // Brief v5 section 3: the whole match's scrap is forfeited, the Level bar does not
            // move, and the retry prompt replays the same match on a new seed.
            out.attempts = attempts + 1
            return out
        }

        let banked = breakdown ?? ScrapBreakdown()
        out.scrap = banked
        out.levelPoints = winPoints(seriesIndex: seriesIndex, flawless: banked.isFlawless, replay: isReplay)

        let before = level(points: points)
        out.pointsAfter = min(max(0, points) + out.levelPoints, maxPoints)
        let after = level(points: out.pointsAfter)

        out.newlyUnlocked = newlyUnlocked(from: before.level, to: after.level)
        out.newPaintJobs = newPaintJobs(from: before.level, to: after.level)
            .filter { !paintSeen.contains($0) }

        if !isReplay {
            out.attempts = 0
            out.matchIndex = matchIndex + 1
            if out.matchIndex >= SeriesProgress.matchesPerSeries {
                out.finishedSeries = true
                if let next = tier.next {
                    if gates.tierAvailable(next) {
                        out.seriesIndex = seriesIndex + 1
                        out.matchIndex = 0
                    } else {
                        // The win stands. The player stays in this Series and can replay it.
                        out.hitTheWall = true
                        out.matchIndex = SeriesProgress.matchesPerSeries
                    }
                } else {
                    out.finishedCampaign = true
                    out.campaignComplete = true
                    out.matchIndex = SeriesProgress.matchesPerSeries
                }
            }
        }

        out.rewards = Rewards(
            scrap: banked,
            levelPoints: out.levelPoints,
            levelBefore: before,
            levelAfter: after,
            series: SeriesProgress(
                seriesIndex: out.seriesIndex,
                matchIndex: out.matchIndex,
                attempts: out.attempts,
                campaignComplete: out.campaignComplete
            ),
            newlyUnlocked: out.newlyUnlocked,
            newPaintJobs: out.newPaintJobs,
            finishedSeries: out.finishedSeries,
            finishedCampaign: out.finishedCampaign,
            hitTheWall: out.hitTheWall
        )
        return out
    }

    // MARK: - Old saves (brief v5 section 9.6)

    /// A career saved before wave P, read forward once: Series is its circuit, the match index is
    /// the ties it had won in that season, and the Level bar is what its lifetime wins would have
    /// paid at Series 1. Scrap, owned parts, rival records and fight logs are untouched.
    ///
    /// Pure on purpose (it takes the model, not a context) so the self test can prove it without a
    /// store. `CareerStore.state(in:)` is the only caller, and calls it once.
    @discardableResult
    static func migrate(_ state: CareerState) -> Bool {
        guard !state.migratedToSeries else { return false }

        // `tier` is computed from `seriesIndex` since wave P, so the old circuit has to be read
        // off the stored text instead.
        let tier = CareerTier.named(state.tierRaw)
        let wonInSeason = state.bracket?.playerWins ?? state.winsThisTier
        let perWin = progression.series(0)?.winPoints ?? 0

        state.seriesIndex = tier.index
        state.matchIndex = min(SeriesProgress.matchesPerSeries - 1, max(0, wonInSeason))
        state.levelPoints = min(maxPoints, max(0, state.wins) * perWin)
        state.attempts = 0
        state.replaySeriesIndex = -1
        state.replayMatchIndex = -1
        state.campaignComplete = state.championshipsWon > 0
        state.paintJobsSeen = []

        // Everything a career starts with is owned, whatever the old save happened to hold.
        var owned = state.blueprints
        for id in startingOwned where !owned.contains(id) { owned.append(id) }
        state.blueprints = owned

        state.migratedToSeries = true
        return true
    }

    /// What a career owns before it has bought anything: `career.starting_unlocks`, which is the
    /// brief's Level 1 loadout plus the plates and the spare battery the first machine is built
    /// from. Trimming that list is the owner's dial for making the ladder start harder.
    static var startingOwned: [String] {
        let listed = catalogue.startingUnlocks
        guard listed.isEmpty else { return listed }
        return progression.levelRequired.filter { $0.value <= 1 }.keys.sorted()
    }

    // MARK: - The shop

    /// Every part in the catalogue, priced, Level gated and wall gated, grouped by kind and then
    /// in ladder order inside each kind (brief v5 section 9.4).
    static func shopEntries(state: CareerState, gates: Gates) -> [ShopEntry] {
        let owned = Set(state.blueprints)
        let level = state.level
        let scrap = state.scrap

        let entries = parts.allPartIDs.compactMap { id -> ShopEntry? in
            guard let category = category(id) else { return nil }
            let required = levelRequired(id)
            let cost = price(id)

            // The wall is answered before the Level, so a locked game says what opens a late part
            // rather than naming a Level the free half can never reach.
            let availability: ShopEntry.Availability
            if owned.contains(id) {
                availability = .owned
            } else if !gates.partAvailable(id) {
                availability = .behindWall
            } else if level < required {
                availability = .needsLevel(required)
            } else if scrap < cost {
                availability = .tooPoor
            } else {
                availability = .buyable
            }

            return ShopEntry(
                id: id,
                name: displayName(id),
                category: category,
                weight: weight(id),
                price: cost,
                levelRequired: required,
                blurb: blurb(id),
                availability: availability
            )
        }

        let order = ShopEntry.Category.allCases
        return entries.sorted { first, second in
            let a = order.firstIndex(of: first.category) ?? 0
            let b = order.firstIndex(of: second.category) ?? 0
            if a != b { return a < b }
            if first.levelRequired != second.levelRequired { return first.levelRequired < second.levelRequired }
            return first.name < second.name
        }
    }

    /// Whether this part can be bought right now, and why not when it cannot. One answer, so a
    /// shop row and `CareerStore.buy` can never disagree.
    static func availability(_ partID: String, state: CareerState, gates: Gates) -> ShopEntry.Availability {
        if state.blueprints.contains(partID) { return .owned }
        if !gates.partAvailable(partID) { return .behindWall }
        let required = levelRequired(partID)
        if state.level < required { return .needsLevel(required) }
        if state.scrap < price(partID) { return .tooPoor }
        return .buyable
    }

    // MARK: - Paint jobs

    /// The ten free milestones of brief v5 section 7, in Level order.
    static func paintJobs(level: Int) -> [PaintJob] {
        progression.paintJobs.map {
            PaintJob(id: $0.id, name: $0.name, level: $0.level, unlocked: level >= $0.level)
        }
    }

    // MARK: - Helpers

    private static func rounded(_ value: Double) -> Int { Int(value.rounded()) }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

    private static func item(_ list: [Double]?, _ index: Int) -> Double? {
        guard let list, list.indices.contains(index) else { return nil }
        return list[index]
    }

    private static func armour(_ damage: FightResult.BotDamage?, _ face: String) -> Double? {
        guard let damage else { return nil }
        switch face {
        case "front": return damage.armour.front
        case "sides": return damage.armour.sides
        case "rear": return damage.armour.rear
        case "top": return damage.armour.top
        default: return nil
        }
    }
}

// MARK: - FightResult v2

extension ProgressionEngine {

    /// The four blocks FightResult v2 adds (docs/wave-p-contracts.md, "FightResult v2"), read
    /// straight from the result text. Every one of them is optional: the arena agent is building
    /// them in the same wave as this, so a result without them has to make a report anyway.
    struct ResultExtras: Equatable {

        struct Hits: Equatable {
            var landed = 0
            var taken = 0
        }

        struct Lost: Equatable {
            var part = ""
            var label = ""
            /// `destroyed` at zero condition, `disabled` for a weapon jammed or cooked.
            var state = ""
        }

        var hits: [String: Hits] = [:]
        var partsLost: [String: [Lost]] = [:]
        var conditionStart: [String: FightResult.BotDamage] = [:]
        var scrap: [String: ScrapBreakdown] = [:]

        var isEmpty: Bool {
            hits.isEmpty && partsLost.isEmpty && conditionStart.isEmpty && scrap.isEmpty
        }

        static func parse(_ json: String) -> ResultExtras {
            guard !json.isEmpty, let data = json.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ResultExtras()
            }
            return ResultExtras(object: root)
        }

        init() {}

        init(object root: [String: Any]) {
            for (id, value) in (root["hits"] as? [String: Any]) ?? [:] {
                guard let entry = value as? [String: Any] else { continue }
                hits[id] = Hits(
                    landed: ResultExtras.number(entry["landed"]),
                    taken: ResultExtras.number(entry["taken"])
                )
            }

            for (id, value) in (root["parts_lost"] as? [String: Any]) ?? [:] {
                guard let list = value as? [Any] else { continue }
                partsLost[id] = list.compactMap { item in
                    guard let entry = item as? [String: Any] else { return nil }
                    return Lost(
                        part: entry["part"] as? String ?? "",
                        label: entry["label"] as? String ?? "",
                        state: entry["state"] as? String ?? ""
                    )
                }
            }

            for (id, value) in (root["condition_start"] as? [String: Any]) ?? [:] {
                guard let entry = value as? [String: Any] else { continue }
                conditionStart[id] = ResultExtras.damage(entry)
            }

            for (id, value) in (root["scrap_breakdown"] as? [String: Any]) ?? [:] {
                guard let entry = value as? [String: Any] else { continue }
                scrap[id] = ScrapBreakdown(
                    base: ResultExtras.number(entry["base"]),
                    damage: ResultExtras.number(entry["damage"]),
                    survivor: ResultExtras.number(entry["survivor"]),
                    flawless: ResultExtras.number(entry["flawless"])
                )
            }
        }

        /// The same condition block shape `FightResult` decodes, so a start block and an end block
        /// can be compared part for part.
        private static func damage(_ entry: [String: Any]) -> FightResult.BotDamage {
            var out = FightResult.BotDamage()
            if let wheels = entry["wheels"] as? [Any] {
                out.wheels = wheels.compactMap { ($0 as? NSNumber)?.doubleValue }
            }
            out.weapon = (entry["weapon"] as? NSNumber)?.doubleValue ?? 1
            out.drive = (entry["drive"] as? NSNumber)?.doubleValue ?? 1
            out.core = (entry["core"] as? NSNumber)?.doubleValue ?? 1
            if let armour = entry["armour"] as? [String: Any] {
                out.armour = FightResult.Armour(
                    front: (armour["front"] as? NSNumber)?.doubleValue ?? 1,
                    sides: (armour["sides"] as? NSNumber)?.doubleValue ?? 1,
                    rear: (armour["rear"] as? NSNumber)?.doubleValue ?? 1,
                    top: (armour["top"] as? NSNumber)?.doubleValue ?? 1
                )
            }
            return out
        }

        private static func number(_ value: Any?) -> Int {
            if let number = value as? NSNumber { return number.intValue }
            if let text = value as? String { return Int(text) ?? 0 }
            return 0
        }
    }
}
