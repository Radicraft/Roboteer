//
//  CareerStore.swift
//  The thin layer between the pure `CareerEngine` and SwiftData: fetch or create the one
//  `CareerState`, keep the eight `RivalRecord`s in step with the catalogue, take the entry fee,
//  write a `FightLog` for every career fight, and settle a damage assessment.
//
//  Everything that decides anything lives in `CareerEngine`. This file only reads and writes.
//

import Foundation
import SwiftData

enum CareerStore {

    /// What a new career starts with: enough to pay the Scrapyard fee and still afford a repair.
    static let openingScrap = 300

    // MARK: - The state

    /// The one career. Created on first use, which is the first time the player opens CAREER.
    @discardableResult
    static func state(in context: ModelContext) -> CareerState {
        if let existing = (try? context.fetch(FetchDescriptor<CareerState>()))?.first {
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

    // MARK: - Entering a season

    /// Pay the fee and draw the bracket. Returns false when the player cannot afford it.
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
    /// `Roboteer/Fixtures/career-regional.json`, a mid Regional season with three machines and one
    /// of them written off.
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
        state.tier = CareerTier.named(root["tier"]?.stringValue ?? "regional")
        state.scrap = root["scrap"]?.intValue ?? 400
        state.blueprints = root["blueprints"]?.stringItems ?? CareerCatalogue.shared.startingUnlocks
        state.garageCapacity = root["garage_capacity"]?.intValue ?? CareerEngine.garageCapacity(state.tier)
        state.fightsPlayed = root["fights_played"]?.intValue ?? 0
        state.wins = root["wins"]?.intValue ?? 0
        state.championshipsWon = root["championships_won"]?.intValue ?? 0
        state.winsThisTier = root["wins_this_tier"]?.intValue ?? 0
        state.currentSeasonSeed = root["season_seed"]?.intValue ?? 424242
        state.seasonTally = SeasonTally.opening(tier: state.tier, entryFee: CareerEngine.entryFee(state.tier))
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

        // The season itself is drawn from the fixture's seed, then run forward by the wins the
        // fixture says the player already has, so the bracket is always consistent with the state.
        var specs: [String: BuildSpec] = [:]
        for rival in CareerCatalogue.shared.rivals {
            specs[rival.id] = CareerEngine.rivalSpec(rival, at: state.tier)
        }
        var bracket = CareerEngine.startSeason(
            tier: state.tier,
            seed: state.currentSeasonSeed,
            player: playerEntrant(from: builds.first { !$0.isWrittenOff }),
            rivals: CareerCatalogue.shared.rivals,
            rivalSpecs: specs
        )
        for _ in 0..<max(0, root["season_wins"]?.intValue ?? state.winsThisTier) {
            bracket = CareerEngine.settlePlayerMatch(bracket, playerWon: true, note: "Knockout")
        }
        state.bracket = bracket

        try? context.save()
        spikeLog.info("-career fixture loaded: \(state.tierRaw, privacy: .public), \(builds.count, privacy: .public) machines, \(state.scrap, privacy: .public) scrap")
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
