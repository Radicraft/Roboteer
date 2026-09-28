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
    /// fitted to any face at any thickness once it is owned. Owner decision 4 (2026-09-24): it is
    /// priced as a FULL COAT, the `armour` factor times `kg_per_unit_area` times the total area of
    /// every face times two units, which is what fitting it everywhere actually weighs: Steel 184,
    /// Reinforced 208, HDPE 61. (It used to be one front plate, 49 for Reinforced, which read as a
    /// rounding error next to a weapon at 144 to 384.)
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

    /// What a material is priced and weighed by in the shop: a full coat, every face at two units.
    static func referencePlateWeight(_ material: Catalogue.Material) -> Double {
        let area = parts.faces.map(\.area).reduce(0, +)
        return material.kgPerUnitArea * (area > 0 ? area : 1) * 2
    }

    /// What the shop row prints as the weight. A part's own weight, and for a material the same
    /// full coat its price is worked out from, so the two numbers agree on the row.
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
    /// A part the player already owns is never announced: the rewards screen says "New in the
    /// shop", and a part in the garage is not new and is not in the shop (bug 5 of
    /// docs/aaa/frontend-meta.md: the starting loadout was announced at wins 1, 2, 6 and 16).
    static func newlyUnlocked(from: Int, to: Int, owned: [String] = []) -> [String] {
        guard to > from else { return [] }
        let held = Set(parts.allPartIDs)
        let mine = Set(owned)
        return progression.levelRequired
            .filter { $0.value > from && $0.value <= to && held.contains($0.key) && !mine.contains($0.key) }
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

    // MARK: - The free game's wall

    /// The last Series this entitlement opens. The free game is the Scrapyard and the Regional,
    /// which is Series 1 and Series 2 (brief section 14); buying opens all five. Read from
    /// `Gates` rather than hard coded, so the one definition of what is free stays in `Gates`.
    static func lastOpenSeries(gates: Gates = Gates.snapshot) -> Int {
        var open = 0
        for tier in CareerTier.allCases where gates.tierAvailable(tier) {
            open = max(open, tier.index)
        }
        return open
    }

    /// True when the match on duty belongs to a Series this entitlement does not open.
    ///
    /// The ENGINE refuses, not the button (coverage row section 14). `settle` already declines to
    /// advance past the wall, but a save can stand on the wrong side of it without ever having
    /// advanced through it: an entitlement that lapses or is revoked, a Family Sharing organiser
    /// who turns it off, a `-career` fixture, or a build run with `-locked`. In every one of those
    /// the save is left exactly as it is, because a StoreKit answer that has not arrived yet must
    /// never cost a player their campaign. What is refused is the MATCH: `nextMatch` returns nil,
    /// the Series screen shows the wall with the unlock as its one primary, and the moment the
    /// entitlement comes back the same save carries on from the same place.
    static func isBehindWall(state: CareerState, gates: Gates = Gates.snapshot) -> Bool {
        guard gates.entitlementSettled else { return false }
        return pending(state).seriesIndex > lastOpenSeries(gates: gates)
    }

    /// Where a save that stopped at the wall moves to once the wall is gone (bug 1 of
    /// docs/aaa/frontend-meta.md). `settle` leaves a walled save at `matchIndex == 4` of the Series
    /// it finished, because the next Series was shut; nothing else ever moved it, so a player who
    /// bought the full game AFTER reaching the wall had no match, no replay and no way on. This is
    /// the one rule that carries such a save across: the Series is finished, it is not the last,
    /// and the next one is now open, so the campaign stands at match 1 of the next Series.
    ///
    /// Nil when there is nothing to do (the save is mid-Series, the campaign is over, or the next
    /// Series is still shut). Pure, so the self test can prove it; `CareerStore.advancePastWall`
    /// writes the answer down on launch and the moment the entitlement arrives.
    static func openedWallAdvance(
        seriesIndex: Int,
        matchIndex: Int,
        campaignComplete: Bool,
        gates: Gates = Gates.snapshot
    ) -> (seriesIndex: Int, matchIndex: Int)? {
        guard !campaignComplete, matchIndex >= SeriesProgress.matchesPerSeries else { return nil }
        let next = seriesIndex + 1
        guard next < SeriesProgress.seriesCount, next <= lastOpenSeries(gates: gates) else { return nil }
        return (next, 0)
    }

    /// `openedWallAdvance`, written onto a career: the next Series at match 1, no attempts, no
    /// replay queued (the campaign has somewhere to go again), and the legacy tier and garage
    /// capacity kept in step the way `CareerStore.settleMatch` keeps them. Works on a model that
    /// is not in any store, so the self test can prove the whole move. True when it moved.
    @discardableResult
    static func carryPastOpenedWall(_ state: CareerState, gates: Gates = Gates.snapshot) -> Bool {
        guard let moved = openedWallAdvance(
            seriesIndex: state.seriesIndex,
            matchIndex: state.matchIndex,
            campaignComplete: state.campaignComplete,
            gates: gates
        ) else { return false }
        state.seriesIndex = moved.seriesIndex
        state.matchIndex = moved.matchIndex
        state.attempts = 0
        state.replaySeriesIndex = -1
        state.replayMatchIndex = -1
        state.tierRaw = state.tier.rawValue
        state.garageCapacity = gates.garageCapacity(forTier: state.tier)
        return true
    }

    /// Everything the next-match card prints and everything the fight config needs, in one place,
    /// so the card, the scouting report and the arena cannot disagree about who is on duty, where,
    /// or what a win pays. Nil when the Series is finished and there is nowhere to go, and nil
    /// when the Series is behind the full game's wall.
    static func nextMatch(state: CareerState, playerBot: BotBuild? = nil, record: RivalRecord? = nil,
                          gates: Gates = Gates.snapshot) -> NextMatch? {
        let replaying = state.isReplaying
        // Owner decision 8: once the campaign is won and no replay is queued, the card is the
        // title defence (PostCampaign.swift), which needs the whole game to be open.
        if state.campaignComplete, !replaying {
            return PostCampaign.defenceMatch(state: state, playerBot: playerBot, gates: gates)
        }
        let (seriesIndex, matchIndex) = pending(state)
        guard !gates.entitlementSettled || seriesIndex <= lastOpenSeries(gates: gates) else { return nil }
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
        let clock = roundClock(seriesIndex: seriesIndex, matchIndex: matchIndex, replay: replaying)

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
            houseBotLine: CareerEngine.houseBotLine(tier: tier, arena: arena, atSeconds: clock.endgameAtS),
            scoutingLine: scoutingLine(for: opponent),
            grudgeLine: grudgeLine(for: opponent, record: record, playerBotName: botName),
            aiSkill: CareerEngine.aiSkill(for: tier),
            temperament: CareerEngine.temperament(for: opponent, seasonSeed: state.currentSeasonSeed),
            scrapRules: scrapRules(seriesIndex: seriesIndex, replay: replaying),
            winPoints: winPoints(seriesIndex: seriesIndex, flawless: false, replay: replaying),
            repairsDue: repairs,
            durationS: clock.durationS,
            endgameAtS: clock.endgameAtS
        )
    }

    /// `rules.duration_s` and `rules.endgame_at_s` for a campaign match. Owner decision 9: the
    /// very first career match (Series 1, match 1, fought for real rather than replayed) is the
    /// two minute opener with the house bot out at 1:20; every other match is the full round.
    static func roundClock(seriesIndex: Int, matchIndex: Int, replay: Bool) -> (durationS: Int, endgameAtS: Int) {
        let round = progression.round
        if seriesIndex == 0, matchIndex == 0, !replay {
            return (round.openerDurationS, round.openerEndgameAtS)
        }
        return (round.durationS, round.endgameAtS)
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
        let board = MedalBoard(held: Set(state.medals))

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
                note: won ? note(for: logs, tier: series.id, round: index) : "",
                medals: board.medals(seriesIndex: seriesIndex, matchIndex: index)
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

        let kind = resultKind(winner: result.outcome.winner, playerID: playerID)

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
            scrap: extras.scrap[playerID],
            judges: result.outcome.type == "judges"
                ? JudgesCard.make(result: result, myID: playerID, myName: botName, theirName: opponentName)
                : nil
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

        func add(_ label: String, _ now: Double?, _ before: Double?, key: String) {
            out.append(PartCondition(
                label: label,
                condition: clamp(now ?? 1),
                startCondition: clamp(before ?? 1),
                key: key
            ))
        }

        add(displayName(spec.weapon), damage?.weapon, start?.weapon, key: "weapon")
        add(displayName(spec.drive), damage?.drive, start?.drive, key: "drive")

        let labels = wheelLabels(count: wheelCount, isTracked: (drive?.tracks ?? 0) > 0)
        for index in 0..<max(0, wheelCount) {
            let label = index < labels.count ? labels[index] : "Wheel \(index + 1)"
            add(label, item(damage?.wheels, index), item(start?.wheels, index), key: PartCondition.key(forLabel: label))
        }

        for face in parts.faces {
            // "Sides" reads as "Side armour"; every other face keeps its catalogue name.
            let faceName = face.name == "Sides" ? "Side" : face.name
            add("\(faceName) armour", armour(damage, face.id), armour(start, face.id), key: "armour_\(face.id)")
        }

        add(displayName(spec.chassis), damage?.core, start?.core, key: "chassis")
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

        /// Wave B (owner decision 3): the medals this win earned, the ones that are new on this
        /// match, their keys for `CareerState.medals`, and what a replay that earned a new one
        /// adds so the match pays in full.
        var medals: [MedalKind] = []
        var newMedals: [MedalKind] = []
        var newMedalKeys: [String] = []
        var medalTopUp: Int = 0

        var didWin: Bool { result == .win }
        /// Everything this match puts in the bank.
        var banked: Int { scrap.total + medalTopUp }
    }

    // MARK: - Medals (owner decision 3, 2026-09-24)

    /// The medals a match earned. All three are on a win only: the win itself; Survivor, which is
    /// the arena's survivor line when the rules paid one and otherwise the machine's own condition
    /// at the end against the start (at least `medals.survivor_min`); and the finisher, a
    /// knockout before the bell or a flawless win (the arena's flawless line when the rules paid
    /// one, otherwise no part lost).
    static func medals(for report: MatchReport, rules: ScrapRules? = nil) -> [MedalKind] {
        guard report.isWin else { return [] }
        let medalRules = progression.medals
        var out: [MedalKind] = [.win]

        let survivor: Bool
        if let scrap = report.scrap, (rules?.survivor ?? 0) > 0 {
            survivor = scrap.survivor > 0
        } else {
            survivor = conditionKept(report) >= medalRules.survivorMin
        }
        if survivor { out.append(.survivor) }

        let flawless: Bool
        if let scrap = report.scrap, (rules?.flawless ?? 0) > 0 {
            flawless = scrap.isFlawless
        } else {
            flawless = report.partsLost.isEmpty
        }
        if medalRules.knockoutOutcomes.contains(report.outcome) || flawless { out.append(.finisher) }
        return out
    }

    /// The machine's condition at the end as a share of what it went out with, over every part the
    /// report lists. 1 when nothing is listed.
    static func conditionKept(_ report: MatchReport) -> Double {
        let start = report.parts.map(\.startCondition).reduce(0, +)
        guard start > 0 else { return 1 }
        return report.parts.map(\.condition).reduce(0, +) / start
    }

    /// The keys of `CareerState.medals` for these medals on this match.
    static func medalKeys(_ kinds: [MedalKind], seriesIndex: Int, matchIndex: Int) -> [String] {
        kinds.map { MedalBoard.key(seriesIndex, matchIndex, $0) }
    }

    /// Brief v5 sections 2, 3, 6 and 9.1 in one pure function: bank the scrap and the points on a
    /// win, move the campaign on, bump the attempt count on anything else.
    static func settle(
        seriesIndex: Int,
        matchIndex: Int,
        attempts: Int,
        points: Int,
        paintSeen: [String] = [],
        owned: [String] = [],
        result: MatchReport.Result,
        breakdown: ScrapBreakdown?,
        isReplay: Bool,
        campaignComplete: Bool,
        medals earned: [MedalKind] = [],
        medalsHeld: [String] = [],
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

        // The wall, enforced rather than drawn. A match fought in a Series this entitlement does
        // not open settles nothing: no scrap, no points, no advance. Nothing can reach here
        // legitimately, because `nextMatch` refuses to hand the match out in the first place, so
        // this is the second lock on the same door.
        guard !gates.entitlementSettled || seriesIndex <= lastOpenSeries(gates: gates) else {
            out.hitTheWall = true
            return out
        }

        guard result == .win else {
            // Brief v5 section 3: the whole match's scrap is forfeited, the Level bar does not
            // move, and the retry prompt replays the same match on a new seed.
            out.attempts = attempts + 1
            return out
        }

        let banked = breakdown ?? ScrapBreakdown()
        out.scrap = banked

        // Owner decision 3: a medal is paid for once. A replay pays `replay_scale`, EXCEPT that a
        // replay which earns a medal for the first time pays the whole match (`new_medal_scale`),
        // so going back for a missing medal is worth the trip. The arena tallied the replay's
        // half on the wire; the rest lands here as a top up, and the points are paid in full.
        let held = Set(medalsHeld)
        out.medals = MedalKind.allCases.filter { earned.contains($0) }
        out.newMedals = out.medals.filter { !held.contains(MedalBoard.key(seriesIndex, matchIndex, $0)) }
        out.newMedalKeys = medalKeys(out.newMedals, seriesIndex: seriesIndex, matchIndex: matchIndex)
        let paysInFull = isReplay && !out.newMedals.isEmpty
        if paysInFull {
            let scale = max(0.0001, progression.replayScale)
            let full = Double(banked.total) / scale * progression.medals.newMedalScale
            out.medalTopUp = max(0, rounded(full) - banked.total)
        }
        out.levelPoints = winPoints(seriesIndex: seriesIndex, flawless: banked.isFlawless,
                                    replay: isReplay && !paysInFull)

        let before = level(points: points)
        out.pointsAfter = min(max(0, points) + out.levelPoints, maxPoints)
        let after = level(points: out.pointsAfter)

        out.newlyUnlocked = newlyUnlocked(from: before.level, to: after.level, owned: owned)
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
            hitTheWall: out.hitTheWall,
            medals: out.medals,
            newMedals: out.newMedals,
            medalTopUp: out.medalTopUp
        )
        return out
    }

    /// Every part id a machine uses, armour materials included, in a stable order: chassis,
    /// drive, weapon, utilities, then the materials front, sides, rear, top.
    static func partIDs(in spec: BuildSpec) -> [String] {
        var ids = [spec.chassis, spec.drive, spec.weapon] + spec.utilities
        for face in ["front", "sides", "rear", "top"] {
            if let material = spec.armour[face]?.material { ids.append(material) }
        }
        for (face, plate) in spec.armour.sorted(by: { $0.key < $1.key })
        where !["front", "sides", "rear", "top"].contains(face) {
            ids.append(plate.material)
        }
        var seen = Set<String>()
        return ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The parts on this machine the career does not own (bug 3 of docs/aaa/frontend-meta.md).
    /// A career match is fought only with parts the player owns: the builder now locks what is
    /// not owned, and FIGHT checks again, because a machine can carry a part from before the
    /// check existed.
    static func unownedParts(in spec: BuildSpec, owned: [String]) -> [String] {
        let mine = Set(owned)
        return partIDs(in: spec).filter { !mine.contains($0) }
    }

    /// The sentence under FIGHT when the machine carries a part the career does not own, or nil.
    static func ownershipFault(in spec: BuildSpec, owned: [String]) -> String? {
        let missing = unownedParts(in: spec, owned: owned)
        guard let first = missing.first else { return nil }
        let name = displayName(first)
        if missing.count == 1 {
            return "\(name) is not yours yet. Buy it in the shop or fit something you own in the garage."
        }
        return "\(name) and \(missing.count - 1) more parts are not yours yet. Buy them in the shop or fit parts you own in the garage."
    }

    /// Why RETRY cannot send this machine straight back in, in one plain sentence that names the
    /// fix, or nil when it can (bug 4 of docs/aaa/frontend-meta.md: RETRY used to be enabled for a
    /// machine with a dead core and landed on "There is no match waiting.").
    ///
    /// `fault` is `BotBuild.fitnessFault`, `legal` is `BotBuild.isValid`, `ownership` is
    /// `ownershipFault`. Repairing clears a fitness fault, so when the bill can be paid the
    /// sentence points at "Repair and retry"; when it cannot, it points at the garage.
    static func retryBlock(fault: String?, legal: Bool, ownership: String?, repairBill: Int, scrap: Int,
                           canPatch: Bool = false) -> String? {
        if let fault {
            if scrap >= repairBill {
                return "\(fault), so it cannot go back in as it is. Repair it for \(repairBill) and retry."
            }
            // The broke-player escape (owner decision 1, docs/aaa/decisions-2026-09-24.md): a
            // free emergency patch-up to 25 %, offered only when the bill cannot be paid and
            // there is no other fit machine to send.
            if canPatch {
                return "\(fault), so it cannot go back in as it is. Repairs cost \(repairBill) and there is \(scrap) in the bank, so the crew will patch it up to \(emergencyPatchPercent)% for free."
            }
            return "\(fault), so it cannot go back in as it is. Repairs cost \(repairBill) and there is \(scrap) in the bank. Send another machine from the garage."
        }
        if !legal { return "Your machine is not legal. Fix it in the garage before the retry." }
        return ownership
    }

    // MARK: - The emergency patch-up (owner decision 1, 2026-09-24)

    /// What the free patch-up brings the core, the weapon, the drive and every wheel up to.
    static let emergencyPatchLevel = 0.25
    static var emergencyPatchPercent: Int { Int((emergencyPatchLevel * 100).rounded()) }

    /// A player is never stranded: when the machine cannot fight, the bill is more than the scrap
    /// in the bank, and there is no other fit machine to send, the crew patches it for free.
    static func emergencyPatchAllowed(fault: String?, repairBill: Int, scrap: Int, otherFitMachine: Bool) -> Bool {
        fault != nil && scrap < repairBill && !otherFitMachine
    }

    /// The damage after the patch-up: the core, the weapon, the drive and each wheel brought up
    /// to `emergencyPatchLevel` if they are below it, armour left exactly as it is. Enough to
    /// clear every fitness fault and nothing more, so the repair bill still means something.
    static func emergencyPatched(_ damage: [String: Any]) -> [String: Any] {
        var out = damage
        let floor = emergencyPatchLevel
        for key in ["core", "weapon", "drive"] {
            out[key] = max(floor, damage[key] as? Double ?? 1.0)
        }
        let wheels = damage["wheels"] as? [Double] ?? []
        out["wheels"] = wheels.map { max(floor, $0) }
        return out
    }

    /// Won, lost or drawn, from the arena's winner id. No winner is a draw. The career's match
    /// report and the quick fight's result sheet both ask this, so neither can call a draw a loss
    /// (bug 8 of docs/aaa/frontend-meta.md).
    static func resultKind(winner: String, playerID: String) -> MatchReport.Result {
        if winner == playerID { return .win }
        if winner.isEmpty { return .draw }
        return .loss
    }

    /// What a rival remembers of one meeting (bug 7 of docs/aaa/frontend-meta.md). A win is a
    /// loss on their record and a loss is a win on it; a draw is neither, so it moves no count and
    /// does not let them gloat as if they had won it. Pure on the model, so the self test can
    /// prove it on a record that is in no store.
    static func remember(_ result: MatchReport.Result, in record: RivalRecord) {
        switch result {
        case .win:
            record.lossesVsPlayer += 1
            record.lastResultWasTheirs = false
        case .loss:
            record.winsVsPlayer += 1
            record.lastResultWasTheirs = true
        case .draw:
            record.lastResultWasTheirs = false
        }
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
