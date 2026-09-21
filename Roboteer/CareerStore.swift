//
//  CareerStore.swift
//  The thin layer between the pure engines and SwiftData: fetch or create the one `CareerState`,
//  migrate a career saved before wave P, keep the eight `RivalRecord`s in step with the catalogue,
//  settle a match, buy a part, and start a replay.
//
//  Everything that decides anything lives in `ProgressionEngine` or `CareerEngine`. This file only
//  reads and writes. Wave P: `settleMatch`, `buy`, `startReplay` and `cancelReplay` are the career
//  flow; `enterSeason`, `settle` and `writeOff` are RETIRED and kept for one wave only, while B1
//  and B2 move the screens that still call them onto the new flow.
//

import Foundation
import SwiftData

enum CareerStore {

    /// What a new career starts with: enough to pay the Scrapyard fee and still afford a repair.
    static var openingScrap: Int { ProgressionEngine.openingScrap }

    // MARK: - The state

    /// The one career. Created on first use, which is the first time the player opens CAREER.
    @discardableResult
    static func state(in context: ModelContext) -> CareerState {
        if let existing = (try? context.fetch(FetchDescriptor<CareerState>()))?.first {
            // Brief v5 section 9.6: a career saved before wave P is read forward once, here, and
            // never again (`migratedToSeries` is the flag). Nothing is lost and nothing crashes.
            if ProgressionEngine.migrate(existing) {
                try? context.save()
                spikeLog.info("career migrated to Series \(existing.seriesIndex + 1, privacy: .public) match \(existing.matchIndex + 1, privacy: .public), Level \(existing.level, privacy: .public)")
            }
            return existing
        }
        let fresh = CareerState(tier: .scrapyard, scrap: openingScrap, seed: Int.random(in: 1...9_999_999))
        context.insert(fresh)
        try? context.save()
        spikeLog.info("career started at the Scrapyard with \(openingScrap, privacy: .public) scrap")
        return fresh
    }

    /// Every rival in the catalogue has a record, created the first time the career is opened so
    /// the scouting screen always has a history to read even when it is an empty one.
    static func prepareRivals(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<RivalRecord>())) ?? []
        let known = Set(existing.map(\.rivalID))
        for rival in CareerCatalogue.shared.rivals where !known.contains(rival.id) {
            let record = RivalRecord(
                rivalID: rival.id,
                name: rival.name,
                roboteer: rival.roboteer,
                liveryHex: rival.liveryHex,
                spec: rival.spec,
                tier: rival.fromTier,
                grudgeLines: rival.grudgeLines
            )
            context.insert(record)
        }
        try? context.save()
    }

    static func record(for rivalID: String, in context: ModelContext) -> RivalRecord? {
        guard !rivalID.isEmpty else { return nil }
        let all = (try? context.fetch(FetchDescriptor<RivalRecord>())) ?? []
        return all.first { $0.rivalID == rivalID }
    }

    // MARK: - Entering a season. RETIRED by wave P (no entry fees, no bracket).

    /// RETIRED (wave P): brief v5 section 9.1 has no entry fee and no bracket. Kept for one wave
    /// because `CareerHomeView` still calls it while B2 rewrites that screen; nothing new may.
    @discardableResult
    static func enterSeason(_ state: CareerState, player: BotBuild?, in context: ModelContext) -> Bool {
        let fee = CareerEngine.entryFee(state.tier)
        guard state.scrap >= fee else { return false }

        prepareRivals(in: context)
        state.scrap -= fee
        state.winsThisTier = 0
        state.currentSeasonSeed = Int.random(in: 1...9_999_999)
        // G5 (wave G): a fresh season starts a fresh tally, so the summary the season screen prints
        // when the final is won is about THIS season and nothing before it.
        state.seasonTally = SeasonTally.opening(tier: state.tier, entryFee: fee)

        // Rivals keep the machine they have been building since the Scrapyard, so their record is
        // brought up to this tier before the draw rather than being rebuilt from the catalogue.
        var specs: [String: BuildSpec] = [:]
        for rival in CareerCatalogue.shared.rivals {
            let spec = CareerEngine.rivalSpec(rival, at: state.tier)
            specs[rival.id] = spec
            if let record = record(for: rival.id, in: context) {
                record.spec = spec
                record.tier = state.tier
            }
        }

        let entrant = playerEntrant(from: player)
        state.bracket = CareerEngine.startSeason(
            tier: state.tier,
            seed: state.currentSeasonSeed,
            player: entrant,
            rivals: CareerCatalogue.shared.rivals,
            rivalSpecs: specs
        )
        try? context.save()
        spikeLog.info("entered the \(state.tier.rawValue, privacy: .public) for \(fee, privacy: .public) scrap, seed \(state.currentSeasonSeed, privacy: .public)")
        return true
    }

    static func playerEntrant(from build: BotBuild?) -> CareerEntrant {
        CareerEntrant(
            id: "player",
            name: build?.name ?? "Your machine",
            roboteer: "You",
            liveryHex: build?.liveryHex ?? LiveryPresets.defaultHex,
            kind: .player,
            spec: build?.spec ?? .defaultWedge
        )
    }

    /// The machine the player is sending out goes into the bracket, so the board shows the right
    /// name and livery for this tie.
    static func setPlayerMachine(_ state: CareerState, to build: BotBuild, in context: ModelContext) {
        guard var bracket = state.bracket, bracket.entrants.indices.contains(bracket.playerIndex) else { return }
        var entrant = bracket.entrants[bracket.playerIndex]
        entrant.name = build.name
        entrant.liveryHex = build.liveryHex
        entrant.spec = build.spec
        bracket.entrants[bracket.playerIndex] = entrant
        state.bracket = bracket
        try? context.save()
    }

    // MARK: - Settling a fight

    /// Everything one career fight changes, worked out in one place so the assessment screen can
    /// show it before any of it is written.
    struct Settlement {
        var didWin = false
        var outcome = "judges"
        var scrapEarned = 0
        var purse = 0
        var bill = RepairBill()
        var newBlueprints: [String] = []
        var rivalLine = ""
        var tookTheTier = false
        var advancedTo: CareerTier?
        /// The tier final was won but the next circuit is behind the wall, so the player stays
        /// where they are and the game offers the unlock once.
        var hitTheWall = false
        var wallSentence = ""
        var newCapacity = 1
        var round = 0
        var arena = "yard"
    }

    /// RETIRED (wave P): `settleMatch` is what settles a career match now. Kept for one wave
    /// because `CareerHomeView` still calls it while B2 rewrites that screen.
    ///
    /// Read the result, write the log, move the bracket on, pay the purse and hand over the
    /// blueprints. The repair bill is worked out but NOT paid here: the player chooses on the
    /// assessment screen whether to repair or write the machine off.
    static func settle(
        state: CareerState,
        bot: BotBuild,
        opponent: CareerEntrant,
        round: Int,
        arena: String,
        result: FightResult?,
        resultJSON: String,
        in context: ModelContext
    ) -> Settlement {
        var settlement = Settlement()
        settlement.round = round
        settlement.arena = arena

        let playerID = CareerFightConfig.playerID
        let damage = result?.damage[playerID]
        settlement.didWin = result?.outcome.winner == playerID
        settlement.outcome = result?.outcome.type ?? "judges"
        settlement.scrapEarned = result?.scrap[playerID] ?? 0
        settlement.bill = CareerEngine.repairBill(for: bot.spec, damage: damage)

        // The machine carries its damage home, exactly as a quick fight does.
        if let damage {
            bot.damageJSON = JSONText.string(from: [
                "wheels": damage.wheels,
                "weapon": damage.weapon,
                "armour": [
                    "front": damage.armour.front,
                    "sides": damage.armour.sides,
                    "rear": damage.armour.rear,
                    "top": damage.armour.top
                ],
                "drive": damage.drive,
                "core": damage.core
            ])
        }
        bot.fights += 1
        if settlement.didWin {
            bot.wins += 1
            if settlement.outcome == "ko" || settlement.outcome == "component_kill" { bot.kos += 1 }
        } else if settlement.outcome == "ko" || settlement.outcome == "component_kill" {
            bot.killedBy = opponent.name
        }

        // The career tally.
        state.fightsPlayed += 1
        if settlement.didWin {
            state.wins += 1
            state.winsThisTier += 1
            settlement.purse = CareerEngine.purse(state.tier, round: round)
            state.scrap += settlement.purse
            settlement.newBlueprints = CareerEngine.newBlueprints(
                tier: state.tier, winsThisTier: state.winsThisTier, held: state.blueprints)
            state.blueprints.append(contentsOf: settlement.newBlueprints)
        }
        state.scrap += settlement.scrapEarned

        // The bracket.
        if let bracket = state.bracket {
            let moved = CareerEngine.settlePlayerMatch(
                bracket, playerWon: settlement.didWin, note: noteFor(result))
            state.bracket = moved
            if moved.playerWonTier {
                settlement.tookTheTier = true
                // The wall lives in one pure function, so the self test can check both sides of it
                // and this reads the gates fresh every time: buy the game later and the next final
                // advances normally.
                let won = CareerEngine.tierWon(at: state.tier, gates: Gates.snapshot)
                if won.wonTheLot {
                    state.championshipsWon += 1
                } else if let next = won.advancedTo {
                    state.tier = next
                    state.winsThisTier = 0
                    settlement.advancedTo = next
                } else if won.hitTheWall {
                    settlement.hitTheWall = true
                    settlement.wallSentence = won.sentence
                }
                state.garageCapacity = CareerEngine.garageCapacity(state.tier)
            }
        }
        settlement.newCapacity = state.garageCapacity

        // G5 (wave G): the season's running total, for the summary of brief v4 section 6. Recorded
        // after the bracket so `tookTheTier` is known, and it keeps the tier the season was fought
        // at even when this win has just moved the player up.
        var tally = state.seasonTally
        if !tally.opened { tally = SeasonTally.opening(tier: state.tier, entryFee: CareerEngine.entryFee(state.tier)) }
        tally.record(
            won: settlement.didWin,
            purse: settlement.purse,
            salvage: settlement.scrapEarned,
            blueprints: settlement.newBlueprints,
            tookTheTier: settlement.tookTheTier
        )
        state.seasonTally = tally

        // The rival's memory and the line they say afterwards.
        if let record = record(for: opponent.rivalID, in: context) {
            if settlement.didWin { record.lossesVsPlayer += 1 } else { record.winsVsPlayer += 1 }
            record.lastResultWasTheirs = !settlement.didWin
            record.lastMet = Date()
            record.lastMetTier = state.tierRaw
            record.lastMetRound = round
            settlement.rivalLine = CareerEngine.grudgeLine(
                lines: record.grudgeLines,
                wins: record.winsVsPlayer,
                losses: record.lossesVsPlayer,
                theyWonLast: !settlement.didWin,
                playerName: record.roboteer,
                botName: bot.name
            )
        }

        // The log, with the replay inputs kept as text for Stage 6.
        let log = FightLog()
        log.date = Date()
        log.tier = state.tier
        log.round = round
        log.opponentID = opponent.id
        log.opponentName = opponent.name
        log.botName = bot.name
        log.outcome = settlement.outcome
        log.didWin = settlement.didWin
        log.scrapEarned = settlement.scrapEarned + settlement.purse
        log.repairCost = settlement.bill.total
        log.arena = arena
        log.resultJSON = resultJSON
        log.replayJSON = replayBlock(from: resultJSON)
        // S6 (stage 6): the configuration this tie was fought with, which is what a replay is
        // played back from. `ArenaHost` keeps the last one it sent.
        log.configJSON = ArenaHost.shared.lastFightConfigJSON
        context.insert(log)

        state.pendingAssessment = true
        try? context.save()
        return settlement
    }

    // MARK: - Wave P: settling a match, buying a part, replaying a win

    /// One career match, settled (brief v5 sections 2, 3, 5 and 6).
    ///
    /// The damage comes home win or lose, because condition carries into the next match unless it
    /// is repaired. Scrap and Level points are banked on a win ONLY: a loss or a draw forfeits the
    /// whole match's scrap, bumps the attempt count and leaves the campaign where it is, which is
    /// what the retry prompt replays. A win moves the match on, and the fourth win of a Series
    /// opens the next one, or hits the full game wall, or finishes the campaign.
    ///
    /// Returns the report B1 shows immediately and, on a win only, the rewards it shows after it.
    @discardableResult
    static func settleMatch(
        state: CareerState,
        bot: BotBuild,
        next: NextMatch,
        result: FightResult?,
        resultJSON: String,
        in context: ModelContext
    ) -> (report: MatchReport, rewards: Rewards?) {

        let playerID = ProgressionEngine.playerID
        // What the machine went out in, read before the new damage is written over it.
        let startDamage = bot.currentDamage
        let report = ProgressionEngine.matchReport(
            result: result,
            spec: bot.spec,
            startDamage: startDamage,
            botName: bot.name,
            opponentName: next.opponent.name,
            resultJSON: resultJSON
        )

        // The machine carries its damage home, exactly as a quick fight does.
        if let damage = result?.damage[playerID] {
            bot.damageJSON = JSONText.string(from: [
                "wheels": damage.wheels,
                "weapon": damage.weapon,
                "armour": [
                    "front": damage.armour.front,
                    "sides": damage.armour.sides,
                    "rear": damage.armour.rear,
                    "top": damage.armour.top
                ],
                "drive": damage.drive,
                "core": damage.core
            ])
        }
        bot.fights += 1
        let byKnockout = report.outcome == "ko" || report.outcome == "component_kill"
        if report.isWin {
            bot.wins += 1
            if byKnockout { bot.kos += 1 }
        } else if byKnockout {
            bot.killedBy = next.opponent.name
        }

        state.fightsPlayed += 1
        if report.isWin { state.wins += 1 }

        // The arena's own breakdown when it sent one, and the legacy total when it did not, so a
        // result from an arena without the v2 blocks still pays the player something.
        let breakdown = report.scrap ?? ScrapBreakdown(base: result?.scrap[playerID] ?? 0)

        let settled = ProgressionEngine.settle(
            seriesIndex: next.seriesIndex,
            matchIndex: next.matchIndex,
            attempts: state.attempts,
            points: state.levelPoints,
            paintSeen: state.paintJobsSeen,
            result: report.result,
            breakdown: breakdown,
            isReplay: next.isReplay,
            campaignComplete: state.campaignComplete,
            gates: Gates.snapshot
        )

        if settled.didWin {
            state.scrap += settled.scrap.total
            state.levelPoints = settled.pointsAfter
            state.paintJobsSeen.append(contentsOf: settled.newPaintJobs)
            if settled.finishedCampaign { state.championshipsWon += 1 }
        }
        state.attempts = settled.attempts
        state.seriesIndex = settled.seriesIndex
        state.matchIndex = settled.matchIndex
        state.campaignComplete = settled.campaignComplete
        // `tierRaw` is the legacy field the logs and the rival records still speak in, so it is
        // kept in step with the Series the player is now in.
        state.tierRaw = state.tier.rawValue
        state.garageCapacity = Gates.snapshot.garageCapacity(forTier: state.tier)
        if next.isReplay {
            state.replaySeriesIndex = -1
            state.replayMatchIndex = -1
        }

        // The rival's memory and the line they say afterwards.
        if let record = record(for: next.opponent.rivalID, in: context) {
            if report.isWin { record.lossesVsPlayer += 1 } else { record.winsVsPlayer += 1 }
            record.lastResultWasTheirs = !report.isWin
            record.lastMet = Date()
            record.lastMetTier = next.tier.rawValue
            record.lastMetRound = next.matchIndex
        }

        // The log, with the replay inputs and the configuration kept as text for the replay list.
        let log = FightLog()
        log.date = Date()
        log.tier = next.tier
        log.round = next.matchIndex
        log.opponentID = next.opponent.id
        log.opponentName = next.opponent.name
        log.botName = bot.name
        log.outcome = report.outcome
        log.didWin = report.isWin
        log.atSeconds = result?.outcome.atSeconds ?? report.durationSeconds
        log.scrapEarned = settled.didWin ? settled.scrap.total : 0
        log.repairCost = CareerEngine.repairBill(for: bot.spec, damage: bot.currentDamage).total
        log.arena = next.arena
        log.resultJSON = resultJSON
        log.replayJSON = replayBlock(from: resultJSON)
        log.configJSON = ArenaHost.shared.lastFightConfigJSON
        context.insert(log)

        // Nothing is left pending: the report and the rewards are shown straight away and the
        // repair is the player's own choice on the Series screen (brief v5 section 9.4).
        state.pendingAssessment = false
        try? context.save()
        spikeLog.info("settled Series \(next.seriesIndex + 1, privacy: .public) match \(next.matchIndex + 1, privacy: .public): \(report.result.rawValue, privacy: .public), \(settled.didWin ? settled.scrap.total : 0, privacy: .public) scrap, \(settled.levelPoints, privacy: .public) points")
        return (report, settled.rewards)
    }

    /// Buy a part with scrap (brief v5 section 3). One gate: the part has to be unowned, in front
    /// of the wall, at or below the player's Level, and affordable. Purchases are permanent and
    /// there is no sell back, so there is nothing to undo.
    @discardableResult
    static func buy(_ partID: String, state: CareerState, in context: ModelContext) -> Bool {
        guard ProgressionEngine.availability(partID, state: state, gates: Gates.snapshot) == .buyable else {
            return false
        }
        let price = ProgressionEngine.price(partID)
        guard price >= 0, state.scrap >= price else { return false }
        state.scrap -= price
        if !state.blueprints.contains(partID) { state.blueprints.append(partID) }
        try? context.save()
        spikeLog.info("bought \(partID, privacy: .public) for \(price, privacy: .public) scrap")
        return true
    }

    /// Replay a match that has already been won (brief v5 section 9.1). Only once the campaign is
    /// finished, or once the next Series is behind the full game wall, and only for a match the
    /// player has actually won. A replay pays `replay_scale` of the scrap and the points, and it
    /// cannot move the campaign on.
    @discardableResult
    static func startReplay(state: CareerState, seriesIndex: Int, matchIndex: Int, in context: ModelContext) -> Bool {
        guard ProgressionEngine.replaysAvailable(state: state, gates: Gates.snapshot),
              ProgressionEngine.isWon(state: state, seriesIndex: seriesIndex, matchIndex: matchIndex) else {
            return false
        }
        state.replaySeriesIndex = seriesIndex
        state.replayMatchIndex = matchIndex
        try? context.save()
        return true
    }

    /// Back out of a replay before it is fought.
    static func cancelReplay(state: CareerState, in context: ModelContext) {
        state.replaySeriesIndex = -1
        state.replayMatchIndex = -1
        try? context.save()
    }

    /// Pay the bill and the machine comes back pristine.
    static func repair(_ bot: BotBuild, bill: RepairBill, state: CareerState, in context: ModelContext) {
        guard state.scrap >= bill.total else { return }
        state.scrap -= bill.total
        bot.repair()
        state.pendingAssessment = false
        try? context.save()
    }

    /// Strip the wreck instead. The machine leaves the garage and its scrap value comes back.
    static func writeOff(_ bot: BotBuild, bill: RepairBill, state: CareerState, in context: ModelContext) {
        state.scrap += bill.scrapForParts
        bot.isWrittenOff = true
        bot.retiredAt = Date()
        bot.isSelected = false
        state.pendingAssessment = false
        try? context.save()
    }

    /// Nothing is spent, the machine stays damaged and the player can settle it later.
    static func defer_(_ state: CareerState, in context: ModelContext) {
        state.pendingAssessment = false
        try? context.save()
    }

    // MARK: - Helpers

    private static func noteFor(_ result: FightResult?) -> String {
        guard let result else { return "" }
        switch result.outcome.type {
        case "ko": return "Knockout at \(Int(result.outcome.atSeconds.rounded())) s"
        case "out_of_arena": return "Out of the arena"
        case "component_kill": return "Core destroyed"
        case "judges": return "Judges decision"
        default: return result.outcome.title
        }
    }

    /// The `replay` block on its own, so Stage 6 does not have to carry the whole result around.
    private static func replayBlock(from json: String) -> String {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let replay = root["replay"],
              let out = try? JSONSerialization.data(withJSONObject: replay, options: []),
              let text = String(data: out, encoding: .utf8) else { return "" }
        return text
    }

    // MARK: - The QA fixture

    /// `-career <fixture.json>` loads a saved career for QA. The file may be a bundle resource
    /// name, a bundle resource path or an absolute path; the shipped one is
    /// `Roboteer/Fixtures/career-regional.json`, a career part way through Series 2 at Level 20
    /// with a damaged machine. The file keeps its name so `-career career-regional.json` still
    /// works for everyone who has it in a script.
    @discardableResult
    static func loadFixtureIfRequested(in context: ModelContext) -> Bool {
        guard let argument = ArenaHost.launchArgument("-career") else { return false }
        guard let text = fixtureText(argument), let root = JSONValue.parse(text) else {
            spikeLog.error("-career \(argument, privacy: .public) did not load")
            return false
        }

        // Start from nothing so a fixture is always the whole truth.
        for build in (try? context.fetch(FetchDescriptor<BotBuild>())) ?? [] { context.delete(build) }
        for career in (try? context.fetch(FetchDescriptor<CareerState>())) ?? [] { context.delete(career) }
        for record in (try? context.fetch(FetchDescriptor<RivalRecord>())) ?? [] { context.delete(record) }
        for log in (try? context.fetch(FetchDescriptor<FightLog>())) ?? [] { context.delete(log) }

        let state = CareerState()
        // `series` is a Series id or a number; `tier` is still read so an older fixture loads.
        let seriesName = root["series"]?.stringValue ?? root["tier"]?.stringValue ?? "regional"
        state.tier = CareerTier.named(seriesName)
        if let index = root["series_index"]?.intValue { state.seriesIndex = max(0, min(4, index)) }
        state.tierRaw = state.tier.rawValue
        state.matchIndex = max(0, min(SeriesProgress.matchesPerSeries,
                                      root["match_index"]?.intValue ?? 0))
        state.levelPoints = max(0, min(ProgressionEngine.maxPoints,
                                       root["level_points"]?.intValue
                                       ?? ProgressionEngine.points(forLevel: root["level"]?.intValue ?? 1)))
        state.attempts = max(0, root["attempts"]?.intValue ?? 0)
        state.campaignComplete = root["campaign_complete"]?.boolValue ?? false
        state.paintJobsSeen = root["paint_jobs_seen"]?.stringItems ?? []
        state.scrap = root["scrap"]?.intValue ?? 400
        state.blueprints = root["owned"]?.stringItems
            ?? root["blueprints"]?.stringItems
            ?? ProgressionEngine.startingOwned
        state.garageCapacity = root["garage_capacity"]?.intValue ?? CareerEngine.garageCapacity(state.tier)
        state.fightsPlayed = root["fights_played"]?.intValue ?? 0
        state.wins = root["wins"]?.intValue ?? 0
        state.championshipsWon = root["championships_won"]?.intValue ?? 0
        state.currentSeasonSeed = root["career_seed"]?.intValue ?? root["season_seed"]?.intValue ?? 424242
        // A fixture is written in the new shape, so it is never migrated on top of.
        state.migratedToSeries = true
        context.insert(state)

        var builds: [BotBuild] = []
        for entry in (root["bots"]?.items ?? []) {
            let build = BotBuild(spec: fixtureSpec(entry))
            build.damageJSON = entry["damage"].map { JSONText.string(from: fixtureDamage($0)) } ?? ""
            build.fights = entry["fights"]?.intValue ?? 0
            build.wins = entry["wins"]?.intValue ?? 0
            build.kos = entry["kos"]?.intValue ?? 0
            build.killedBy = entry["killed_by"]?.stringValue ?? ""
            build.isWrittenOff = entry["written_off"]?.boolValue ?? false
            if build.isWrittenOff { build.retiredAt = Date() }
            context.insert(build)
            builds.append(build)
        }
        if let first = builds.first(where: { !$0.isWrittenOff }) {
            Garage.select(first, in: builds)
        }

        prepareRivals(in: context)
        for entry in (root["rivals"]?.items ?? []) {
            guard let id = entry["id"]?.stringValue, let record = record(for: id, in: context) else { continue }
            record.winsVsPlayer = entry["wins_vs_player"]?.intValue ?? 0
            record.lossesVsPlayer = entry["losses_vs_player"]?.intValue ?? 0
            record.lastMetTier = entry["last_met_tier"]?.stringValue ?? ""
            record.lastMetRound = entry["last_met_round"]?.intValue ?? -1
            record.lastResultWasTheirs = entry["last_result_was_theirs"]?.boolValue
                ?? (record.winsVsPlayer > record.lossesVsPlayer)
            if record.winsVsPlayer + record.lossesVsPlayer > 0 { record.lastMet = Date() }
            record.spec = CareerEngine.rivalSpec(
                CareerCatalogue.shared.rival(id) ?? CareerCatalogue.shared.rivals[0], at: state.tier)
        }

        // Wave P: there is no bracket to redraw. The Series, the match and the Level bar ARE the
        // state, and the opponents follow from the career seed, so a fixture cannot disagree with
        // itself the way a stored bracket could.

        try? context.save()
        spikeLog.info("-career fixture loaded: Series \(state.seriesIndex + 1, privacy: .public) match \(state.matchIndex + 1, privacy: .public), Level \(state.level, privacy: .public), \(builds.count, privacy: .public) machines, \(state.scrap, privacy: .public) scrap")
        return true
    }

    private static func fixtureText(_ argument: String) -> String? {
        if let text = try? String(contentsOfFile: argument, encoding: .utf8) { return text }
        let name = (argument as NSString).deletingPathExtension.components(separatedBy: "/").last ?? argument
        if let url = Bundle.main.url(forResource: name, withExtension: "json"),
           let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        return nil
    }

    private static func fixtureSpec(_ value: JSONValue) -> BuildSpec {
        var armour: [String: ArmourFaceSpec] = [:]
        for member in (value["armour"]?.members ?? []) {
            armour[member.key] = ArmourFaceSpec(
                material: member.value["material"]?.stringValue ?? "hdpe",
                thickness: member.value["thickness"]?.intValue ?? 1
            )
        }
        if armour.isEmpty { armour = BuildSpec.defaultWedge.armour }
        return BuildSpec(
            name: value["name"]?.stringValue ?? "Fixture bot",
            chassis: value["chassis"]?.stringValue ?? "wedge",
            drive: value["drive"]?.stringValue ?? "4wd",
            weapon: value["weapon"]?.stringValue ?? "flipper",
            utilities: value["utility"]?.stringItems ?? ["srimech"],
            armour: armour,
            liveryHex: value["livery"]?.stringValue ?? LiveryPresets.defaultHex
        )
    }

    private static func fixtureDamage(_ value: JSONValue) -> [String: Any] {
        let armour = value["armour"]
        return [
            "wheels": (value["wheels"]?.items ?? []).compactMap { $0.doubleValue },
            "weapon": value["weapon"]?.doubleValue ?? 1.0,
            "armour": [
                "front": armour?["front"]?.doubleValue ?? 1.0,
                "sides": armour?["sides"]?.doubleValue ?? 1.0,
                "rear": armour?["rear"]?.doubleValue ?? 1.0,
                "top": armour?["top"]?.doubleValue ?? 1.0
            ],
            "drive": value["drive"]?.doubleValue ?? 1.0,
            "core": value["core"]?.doubleValue ?? 1.0
        ]
    }
}
