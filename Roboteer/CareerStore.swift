//
//  CareerStore.swift
//  The thin layer between the pure engines and SwiftData: fetch or create the one `CareerState`,
//  migrate a career saved before wave P, keep the eight `RivalRecord`s in step with the catalogue,
//  settle a match, buy a part, and start a replay.
//
//  Everything that decides anything lives in `ProgressionEngine` or `CareerEngine`. This file only
//  reads and writes. Wave P: `settleMatch`, `buy`, `startReplay` and `cancelReplay` are the career
//  flow. `enterSeason`, `settle`, `writeOff` and the season's `Settlement` were RETIRED with the
//  bracket and DELETED by B2 (2026-09-21) once no screen called them; the entry fee, the purse and
//  the write off went with them (brief v5 section 9.1).
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
            // A save that stopped at the wall and has since been bought (or restored) on a
            // previous run carries on from here (bug 1).
            advancePastWall(existing, in: context)
            return existing
        }
        let fresh = CareerState(tier: .scrapyard, scrap: openingScrap, seed: Int.random(in: 1...9_999_999))
        context.insert(fresh)
        try? context.save()
        spikeLog.info("career started at the Scrapyard with \(openingScrap, privacy: .public) scrap")
        return fresh
    }

    /// Carry a save that stopped at the full game wall into the next Series once that Series is
    /// open (bug 1 of docs/aaa/frontend-meta.md). Called whenever the career is fetched, which
    /// covers a relaunch after buying or restoring, and by the career screen the moment the
    /// entitlement turns true while it is up. A replay that was queued behind the wall is dropped,
    /// because the campaign has somewhere to go again. Returns true when the save moved.
    @discardableResult
    static func advancePastWall(_ state: CareerState, gates: Gates = Gates.snapshot,
                                in context: ModelContext) -> Bool {
        guard ProgressionEngine.carryPastOpenedWall(state, gates: gates) else { return false }
        try? context.save()
        spikeLog.info("the wall opened: career carried on to Series \(state.seriesIndex + 1, privacy: .public) match 1")
        return true
    }

    /// The same, for whatever career is saved, without creating one. The app root calls this at
    /// launch (after a `-career` fixture has loaded) and whenever the entitlement changes, so the
    /// menu's next-match card and the Series screen agree the moment the purchase lands.
    @discardableResult
    static func advanceSavedCareerPastWall(in context: ModelContext) -> Bool {
        guard let existing = (try? context.fetch(FetchDescriptor<CareerState>()))?.first else { return false }
        return advancePastWall(existing, in: context)
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
            owned: state.blueprints,
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
            ProgressionEngine.remember(report.result, in: record)
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

    /// The free emergency patch-up (owner decision 1). Refuses unless
    /// `ProgressionEngine.emergencyPatchAllowed` says the player is truly stranded.
    @discardableResult
    static func emergencyPatch(_ bot: BotBuild, state: CareerState, otherFitMachine: Bool,
                               in context: ModelContext) -> Bool {
        let bill = CareerEngine.repairBill(for: bot.spec, damage: bot.currentDamage).total
        guard ProgressionEngine.emergencyPatchAllowed(fault: bot.fitnessFault, repairBill: bill,
                                                      scrap: state.scrap, otherFitMachine: otherFitMachine) else {
            return false
        }
        bot.damageJSON = JSONText.string(from: ProgressionEngine.emergencyPatched(bot.damageDictionary))
        try? context.save()
        spikeLog.info("emergency patch-up on \(bot.name, privacy: .public): bill \(bill, privacy: .public), scrap \(state.scrap, privacy: .public)")
        return true
    }

    // MARK: - Helpers

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
