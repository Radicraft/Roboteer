//
//  CareerSelfTest.swift
//  There is no test target in this project, so the career carries its own tests. Launch with
//  `-careerSelfTest` and it runs the whole of brief v5's progression through `ProgressionEngine`
//  and `CareerEngine` before the first screen appears, printing one PASS or FAIL line per check
//  and then a summary.
//
//  Wave P: the scripted season, the bracket's shape and the season summary are gone with the
//  season. What is scripted now is the twenty match campaign of brief v5: Level 100 on the last
//  final, the scrap a player can actually earn against what the shop actually charges, a loss that
//  banks nothing, a replay that pays half, and a career saved before this wave read forward.
//
//  Everything it touches is pure: no SwiftData writes, no SwiftUI, no arena. It is safe to run at
//  launch and it changes nothing. `HARNESS` is defined when these files are compiled as a command
//  line binary on a Mac (docs/wave-p-a-notes.md), where the few checks that need a SwiftUI file
//  are skipped.
//

import Foundation

enum CareerSelfTest {

    private static var passes = 0
    private static var failures: [String] = []
    private static var warnings: [String] = []

    static func runIfRequested() {
        guard ArenaHost.hasLaunchFlag("-careerSelfTest") else { return }
        run()
    }

    @discardableResult
    static func run() -> Bool {
        passes = 0
        failures = []
        warnings = []
        say("career self test starting")

        checkCatalogue()
        checkProgressionBlock()
        checkLadder()
        checkBuilds()
        checkPrices()
        checkShopPrices()
        checkRepairBill()
        checkLevelBar()
        checkCampaign()
        checkLossAndRetry()
        checkNextMatchCard()
        checkSeriesSlots()
        checkMatchReport()
        checkShop()
        checkPaintJobs()
        checkMigration()
        checkRivalMemory()
        checkTheWall()
        checkHouseBots()
        checkHouseBotChoice()
        checkOpponentHeads()
        checkPlainWords()
        checkFrontEndFixes()
        checkMedals()
        checkOpener()
        checkOneGarage()
        checkTaster()
        checkLadderExhibition()
        checkDefence()
        checkDaily()
        checkPacing()

        if failures.isEmpty {
            say("career self test: ALL PASS (\(passes) checks, \(warnings.count) warnings)")
            return true
        }
        say("career self test: \(failures.count) FAILED of \(passes + failures.count)")
        for line in failures { say("  FAILED: \(line)") }
        return false
    }

    // MARK: - The catalogue

    private static func checkCatalogue() {
        let catalogue = CareerCatalogue.shared
        check("the catalogue has five Series", catalogue.tiers.count == 5)
        check("the catalogue has eight rivals", catalogue.rivals.count == 8)
        check("the catalogue has five bosses", catalogue.bosses.count == 5)
        check("every price factor is present", ["chassis", "weapon", "drive", "armour", "utility"]
            .allSatisfy { catalogue.economy.factor($0) > 0 })
        check("the write off threshold is 0.7", abs(catalogue.economy.writeOffThreshold - 0.7) < 0.0001)
        check("scrap for parts is 0.4", abs(catalogue.economy.scrapForParts - 0.4) < 0.0001)

        for tier in CareerTier.allCases {
            guard let entry = catalogue.tier(tier) else {
                check("Series \(tier.index + 1) is in the catalogue", false)
                continue
            }
            check("Series \(tier.index + 1) index agrees with the enum", entry.index == tier.index)
            check("Series \(tier.index + 1) arenas all exist",
                  entry.arenas.allSatisfy { Catalogue.shared.arena($0) != nil })
        }

        let capacities = CareerTier.allCases.map { CareerEngine.garageCapacity($0) }
        check("garage capacity grows 1 to 5 with the Series", capacities == [1, 2, 3, 4, 5])
        check("the free Series are 1 and 2",
              catalogue.tiers.filter(\.free).map(\.id).sorted() == ["regional", "scrapyard"])

        let ids = Catalogue.shared.allPartIDs
        check("every part id is unique", Set(ids).count == ids.count)
        check("the catalogue has parts to sell", ids.count > 20, detail: "\(ids.count)")

        // D6 (docs/wave-a-drives-ai-notes.md): the "Turn" pips show what a drive measurably
        // pivots at, not the catalogue `turn_rate` the arena scales through its scrub gain.
        let drives = Catalogue.shared.drives
        check("every drive has a measured turn rate", drives.allSatisfy { $0.measuredTurnRate != nil },
              detail: drives.filter { $0.measuredTurnRate == nil }.map(\.id).joined(separator: " "))
        let ordered = drives.allSatisfy { a in
            drives.allSatisfy { b in a.displayTurnRate <= b.displayTurnRate || a.turnPips >= b.turnPips }
        }
        check("the Turn pips follow the measured turn rate", ordered,
              detail: drives.map { "\($0.id) \($0.displayTurnRate) \($0.turnPips)" }.joined(separator: ", "))
        if let fourWD = Catalogue.shared.drives.first(where: { $0.id == "4wd" }),
           let tracks = Catalogue.shared.drives.first(where: { $0.id == "tracks" }),
           let sixWD = Catalogue.shared.drives.first(where: { $0.id == "6wd" }) {
            check("4WD shows a quicker turn than 6WD and tracks, as it pivots",
                  fourWD.turnPips > sixWD.turnPips && sixWD.turnPips > tracks.turnPips,
                  detail: "4wd \(fourWD.turnPips) 6wd \(sixWD.turnPips) tracks \(tracks.turnPips)")
        }
    }

    /// The `progression` block of `Shared/parts.json`, which is where every number in brief v5
    /// lives. Nothing in the engine may invent one, so the block's shape is checked first.
    private static func checkProgressionBlock() {
        let progression = CareerCatalogue.shared.progression
        check("the progression block loaded", !progression.isEmpty)
        check("a Level is a hundred points", progression.pointsPerLevel == 100)
        check("the Level cap is a hundred", progression.levelCap == 100)
        check("the free game's Level cap is 33", progression.freeLevelCap == 33)
        check("a flawless win pays a quarter more points",
              abs(progression.flawlessPointsBonus - 0.25) < 0.0001)
        check("a replay pays half", abs(progression.replayScale - 0.5) < 0.0001)
        check("five Series ship", progression.series.count == SeriesProgress.seriesCount)

        for (index, series) in progression.series.enumerated() {
            let name = "Series \(index + 1)"
            check("\(name) is in order", series.index == index && series.number == index + 1)
            check("\(name) is a circuit that exists", CareerCatalogue.shared.tier(series.id) != nil)
            check("\(name) is four matches", series.matches.count == SeriesProgress.matchesPerSeries)
            check("\(name) ends with its final",
                  series.matches.last?.isFinal == true
                  && series.matches.dropLast().allSatisfy { !$0.isFinal })
            check("\(name) has at least one arena and they all exist",
                  !series.arenas.isEmpty && series.arenas.allSatisfy { Catalogue.shared.arena($0) != nil })
            check("\(name) names a real opponent in every match",
                  series.matches.allSatisfy { $0.isFiller || CareerCatalogue.shared.rival($0.opponent) != nil })
            check("\(name) pays points for a win", series.winPoints > 0)
            check("\(name) has a scrap rate for every line",
                  series.scrap.base > 0 && series.scrap.damageFull > 0
                  && series.scrap.survivor > 0 && series.scrap.flawless > 0)
            check("\(name) survivor line is seven tenths of the machine",
                  abs(series.scrap.survivorMin - 0.7) < 0.0001)
        }

        let points = progression.series.map(\.winPoints)
        check("a later Series always pays more points",
              zip(points, points.dropFirst()).allSatisfy { $0 < $1 }, detail: "\(points)")
        let base = progression.series.map(\.scrap.base)
        check("a later Series always pays more scrap",
              zip(base, base.dropFirst()).allSatisfy { $0 < $1 }, detail: "\(base)")

        check("Series 4 alternates its two arenas",
              progression.series(3)?.arena(matchIndex: 0) == "furnace"
              && progression.series(3)?.arena(matchIndex: 1) == "crush"
              && progression.series(3)?.arena(matchIndex: 2) == "furnace")
        check("a one arena Series fights every match there",
              (0..<4).allSatisfy { progression.series(0)?.arena(matchIndex: $0) == "yard" })

        check("the Series' names are the circuits' names",
              (0..<5).allSatisfy { ProgressionEngine.seriesName($0) == CareerTier.allCases[$0].title })
        check("a Series is titled with its number and its name",
              ProgressionEngine.seriesLine(1) == "Series 2: Regional",
              detail: ProgressionEngine.seriesLine(1))
    }

    /// The Level ladder of brief v5 section 7, at the brief's own numbers.
    private static func checkLadder() {
        let progression = CareerCatalogue.shared.progression
        let parts = Catalogue.shared
        let held = Set(parts.allPartIDs)

        check("every part in the catalogue is on the ladder",
              parts.allPartIDs.allSatisfy { progression.levelRequired[$0] != nil },
              detail: parts.allPartIDs.filter { progression.levelRequired[$0] == nil }.joined(separator: ", "))

        // The thirteen new parts are D1's and D2's to add. Until they land this is a warning, and
        // when they land it becomes a pass, exactly as the contracts file asks.
        let missing = progression.levelRequired.keys.filter { !held.contains($0) }.sorted()
        if missing.isEmpty {
            check("every id on the ladder exists in the catalogue", true)
        } else {
            warn("\(missing.count) ladder ids are not in the catalogue yet (D1 and D2 add them): \(missing.joined(separator: ", "))")
        }

        // Brief v5 section 7, item by item, with the owner's 2026-09-24 moves (decisions 5 and 6):
        // the Saw is the first purchase at Level 4, and the Overcharge core, the Vortex spinner
        // and the Apex hull come forward so the last final is fought with them.
        let brief: [(String, Int)] = [
            ("flipper", 1), ("saw", 4), ("reinforced", 10), ("tracks", 15), ("ram", 20),
            ("horizontal_spinner", 25), ("legs", 30), ("shock_prod", 35), ("flamethrower", 40),
            ("reactive", 45), ("crusher", 50), ("hover", 55), ("tesla_arc", 60),
            ("drill_lance", 65), ("titanium", 70), ("twin_saw", 75), ("napalm_cannon", 80),
            ("adaptive_tracks", 85), ("overcharge_core", 85), ("vortex_spinner", 90), ("apex", 93)
        ]
        for (id, level) in brief {
            check("\(id) unlocks at Level \(level)", ProgressionEngine.levelRequired(id) == level,
                  detail: "\(ProgressionEngine.levelRequired(id))")
        }
        check("the brief's ladder is twenty one items", brief.count == 21)

        check("the starting loadout is Level 1",
              ["wedge", "box", "2wd", "4wd", "flipper", "steel", "hdpe", "srimech"]
                  .allSatisfy { ProgressionEngine.levelRequired($0) == 1 })
        check("nothing on the ladder is outside 1 to the cap",
              progression.levelRequired.values.allSatisfy { $0 >= 1 && $0 <= progression.levelCap })
        // Decision 6 moved Apex to 95, so the cap opens a paint job (Champion gold) rather than a part.
        check("something is unlocked at the cap",
              progression.levelRequired.values.contains(progression.levelCap)
              || progression.paintJobs.contains { $0.level == progression.levelCap })
        check("the Saw is not in the starting loadout (decision 5)",
              !CareerCatalogue.shared.startingUnlocks.contains("saw"))
        check("the Saw is buyable after the first win (Level 4 at 350 points)",
              ProgressionEngine.level(points: 350).level >= ProgressionEngine.levelRequired("saw")
              && ProgressionEngine.openingScrap + 144 >= ProgressionEngine.price("saw"),
              detail: "price \(ProgressionEngine.price("saw"))")
        // Wins 1 to 19 with no flawless bonus: the Level the Series 5 final is fought at.
        var beforeFinal = 0
        for series in 0..<SeriesProgress.seriesCount {
            let wins = series == SeriesProgress.seriesCount - 1 ? SeriesProgress.matchesPerSeries - 1
                : SeriesProgress.matchesPerSeries
            beforeFinal += (progression.series(series)?.winPoints ?? 0) * wins
        }
        let finalLevel = ProgressionEngine.level(points: beforeFinal).level
        check("the final three open before the Series 5 final (decision 6)",
              ["overcharge_core", "vortex_spinner", "apex"].allSatisfy { ProgressionEngine.levelRequired($0) <= finalLevel },
              detail: "the final is fought at Level \(finalLevel)")

        let levels = Set(progression.levelRequired.values).sorted()
        let gap = zip(levels, levels.dropFirst()).map { $1 - $0 }.max() ?? 0
        check("the ladder has something new at least every five Levels", gap <= 5,
              detail: "biggest gap \(gap)")

        // The three renames of brief v5 section 9.5, which are names only: the ids do not move.
        check("ram reads Ram plow", ProgressionEngine.displayName("ram") == "Ram plow")
        check("horizontal_spinner reads Spinner blade",
              ProgressionEngine.displayName("horizontal_spinner") == "Spinner blade")
        check("tracks reads Tracked wheels",
              ProgressionEngine.displayName("tracks") == "Tracked wheels")
        check("a part with no display name keeps the catalogue's",
              ProgressionEngine.displayName("flipper") == Catalogue.shared.weapon("flipper")?.name)
        check("an unknown id still prints as words",
              ProgressionEngine.displayName("no_such_part") == "No such part")
    }

    // MARK: - Builds and money

    private static func checkBuilds() {
        for rival in CareerCatalogue.shared.rivals {
            check("rival \(rival.name) starts legal", BuildRules.isValid(rival.spec),
                  detail: BuildRules.errors(rival.spec).joined(separator: " "))
            check("rival \(rival.name) has three grudge lines", rival.grudgeLines.count == 3)
            check("rival \(rival.name) is not gold", rival.liveryHex.lowercased() != "#f2c14e")
            for tier in CareerTier.allCases {
                let spec = CareerEngine.rivalSpec(rival, at: tier)
                check("rival \(rival.name) is legal in Series \(tier.index + 1)", BuildRules.isValid(spec),
                      detail: BuildRules.errors(spec).joined(separator: " "))
            }
        }
        for boss in CareerCatalogue.shared.bosses {
            check("boss \(boss.name) is legal", BuildRules.isValid(boss.spec),
                  detail: BuildRules.errors(boss.spec).joined(separator: " "))
            check("boss \(boss.name) has a signature and an AI mode",
                  !boss.signature.isEmpty && !boss.aiMode.isEmpty)
        }
        check("the five bosses are the brief's five",
              CareerCatalogue.shared.bosses.map(\.name).sorted()
              == ["ANVIL", "BANDSAW", "CINDER", "GRUDGE", "THRESHER"])

        // Filler machines are made by rule, so every one of them has to come out legal.
        var illegal = 0
        for tier in CareerTier.allCases {
            for seed in 1...40 {
                var rng = SeededRandom(seed: seed &* (tier.index &+ 1))
                let entrant = CareerEngine.fillerEntrant(index: seed % 8, tier: tier, rng: &rng)
                if !BuildRules.isValid(entrant.spec) { illegal += 1 }
            }
        }
        check("two hundred filler machines are all legal", illegal == 0, detail: "\(illegal) were not")

        // Wave P: a filler is built from what the LADDER has opened by the end of its Series.
        let early = CareerEngine.fillerPool(tier: .scrapyard)
        let late = CareerEngine.fillerPool(tier: .masters)
        check("a Series 1 filler is built from early parts", !early.contains("full_body_spinner"))
        check("a Series 5 filler may use anything the ladder has opened", late.isSuperset(of: early))
        check("the whole catalogue is open to a Series 5 filler",
              Catalogue.shared.allPartIDs.allSatisfy { late.contains($0) })
    }

    private static func checkPrices() {
        let spec = BuildSpec.tinribs
        let value = CareerEngine.buildValue(spec)
        check("Tinribs is worth something", value > 0)

        var wrecked = FightResult.BotDamage()
        wrecked.wheels = [0, 0, 0, 0]
        wrecked.weapon = 0
        wrecked.drive = 0
        wrecked.core = 0
        wrecked.armour = FightResult.Armour(front: 0, sides: 0, rear: 0, top: 0)
        let bill = CareerEngine.repairBill(for: spec, damage: wrecked)
        check("a total wreck costs its own value to repair", abs(bill.total - value) <= 1,
              detail: "bill \(bill.total), value \(value)")
        check("a total wreck is a write off", bill.isWriteOff)
        check("a wreck strips for four tenths of its value",
              bill.scrapForParts == Int((Double(value) * 0.4).rounded()))
    }

    /// The shop's prices are the same `price_factor x weight` the repair bill has always used.
    private static func checkShopPrices() {
        let money = CareerCatalogue.shared.economy
        guard let weapon = Catalogue.shared.weapon("saw"),
              let drive = Catalogue.shared.drive("4wd"),
              let chassis = Catalogue.shared.chassis("box"),
              let utility = Catalogue.shared.utility("srimech"),
              let material = Catalogue.shared.material("steel") else {
            check("the parts the price checks use are in the catalogue", false)
            return
        }
        check("a weapon is priced at its factor times its weight",
              ProgressionEngine.price("saw") == Int((weapon.weight * money.factor("weapon")).rounded()))
        check("a drive is priced at its factor times its weight",
              ProgressionEngine.price("4wd") == Int((drive.weight * money.factor("drive")).rounded()))
        check("a chassis is priced at its factor times its weight",
              ProgressionEngine.price("box") == Int((chassis.weight * money.factor("chassis")).rounded()))
        check("a utility is priced at its factor times its weight",
              ProgressionEngine.price("srimech") == Int((utility.weight * money.factor("utility")).rounded()))
        check("utilities are priced at factor 20 (decision 4)", money.factor("utility") == 20)
        let utilityPrices = Catalogue.shared.allPartIDs.filter { Catalogue.shared.utility($0) != nil }
            .map { ProgressionEngine.price($0) }
        check("utilities cost 60 to 180 (decision 4)",
              (utilityPrices.min() ?? 0) >= 60 && (utilityPrices.max() ?? 0) <= 180,
              detail: "\(utilityPrices.min() ?? 0) to \(utilityPrices.max() ?? 0)")

        // Owner decision 4: a material is bought once and fitted anywhere, so it is priced as a
        // FULL COAT: every face's area at two units.
        let area = Catalogue.shared.faces.map(\.area).reduce(0, +)
        check("a material is priced as a full coat, every face at two units",
              ProgressionEngine.price("steel")
              == Int((money.factor("armour") * material.kgPerUnitArea * area * 2).rounded()),
              detail: "\(ProgressionEngine.price("steel"))")
        check("the full coat prices are the owner's (Steel 184, Reinforced 208, HDPE 61)",
              ProgressionEngine.price("steel") == 184 && ProgressionEngine.price("reinforced") == 208
              && ProgressionEngine.price("hdpe") == 61,
              detail: "\(ProgressionEngine.price("steel")), \(ProgressionEngine.price("reinforced")), \(ProgressionEngine.price("hdpe"))")
        check("a heavier material costs more",
              ProgressionEngine.price("steel") > ProgressionEngine.price("hdpe"))
        check("every part in the catalogue has a price",
              Catalogue.shared.allPartIDs.allSatisfy { ProgressionEngine.price($0) > 0 })
        check("an unknown part is free rather than a crash",
              ProgressionEngine.price("no_such_part") == 0)
    }

    private static func checkRepairBill() {
        let spec = BuildSpec.tinribs

        let pristine = CareerEngine.repairBill(for: spec, damage: FightResult.BotDamage(
            wheels: [1, 1, 1, 1], weapon: 1, armour: FightResult.Armour(), drive: 1, core: 1))
        check("a pristine machine costs nothing to repair", pristine.total == 0)
        check("a pristine machine is not a write off", pristine.isWriteOff == false)

        var light = FightResult.BotDamage()
        light.wheels = [1, 0.8, 1, 1]
        light.weapon = 0.9
        light.drive = 1
        light.core = 1
        light.armour = FightResult.Armour(front: 0.7, sides: 1, rear: 1, top: 1)
        let lightBill = CareerEngine.repairBill(for: spec, damage: light)
        check("light damage costs something but is not a write off",
              lightBill.total > 0 && !lightBill.isWriteOff,
              detail: "\(lightBill.total) of \(lightBill.buildValue)")
        check("the bill itemises only the parts that were hurt",
              lightBill.items.allSatisfy { $0.lost > 0 })
        check("the itemised costs add up to the total",
              abs(lightBill.items.map(\.cost).reduce(0, +) - lightBill.total) <= lightBill.items.count)

        let value = Double(CareerEngine.buildValue(spec))
        var half = FightResult.BotDamage()
        half.wheels = [1, 1, 1, 1]
        half.weapon = 1
        half.drive = 1
        half.core = 0.31
        let core = CareerEngine.repairBill(for: spec, damage: half)
        check("the write off line is seven tenths of the machine's value",
              core.isWriteOff == (Double(core.total) > 0.7 * value))
    }

    // MARK: - Level

    private static func checkLevelBar() {
        let perLevel = CareerCatalogue.shared.progression.pointsPerLevel
        check("a new career is Level 1", ProgressionEngine.level(points: 0).level == 1)
        check("one Level of points is Level 2", ProgressionEngine.level(points: perLevel).level == 2)
        check("the bar fills across a Level",
              abs(ProgressionEngine.level(points: perLevel + perLevel / 2).fraction - 0.5) < 0.0001)
        check("the bar starts empty", ProgressionEngine.level(points: 0).fraction == 0)
        check("the cap is reached at its own points",
              ProgressionEngine.level(points: ProgressionEngine.maxPoints).level == 100
              && ProgressionEngine.level(points: ProgressionEngine.maxPoints).isCapped)
        check("nothing goes past the cap",
              ProgressionEngine.level(points: ProgressionEngine.maxPoints * 4).level == 100)
        check("a capped bar reads as full",
              ProgressionEngine.level(points: ProgressionEngine.maxPoints).fraction == 1)
        check("Level 50 starts at 4,900 points", ProgressionEngine.points(forLevel: 50) == 4_900)
        check("negative points are Level 1", ProgressionEngine.level(points: -500).level == 1)

        check("the Series each reach the Level the ladder expects",
              (0..<5).map { ProgressionEngine.seriesLevelCeiling($0) } == [15, 33, 53, 75, 100],
              detail: (0..<5).map { "\(ProgressionEngine.seriesLevelCeiling($0))" }.joined(separator: ", "))
        check("winning the free half reaches exactly the free Level cap",
              ProgressionEngine.seriesLevelCeiling(1) == CareerCatalogue.shared.progression.freeLevelCap)
    }

    // MARK: - The campaign

    /// One player, twenty matches, every one of them won with base plus half the damage bonus plus
    /// the survivor bonus, which is what a competent player actually earns. This is the run every
    /// balance number in docs/wave-p-a-notes.md is measured from.
    private struct Campaign {
        /// The Level and the scrap in hand after each win.
        var wins: [(level: Int, scrap: Int, points: Int)] = []
        var finals = 0
        var points = 0
        var scrap = 0
        var complete = false
    }

    private static func runCampaign(flawless: Bool = false) -> Campaign {
        var out = Campaign()
        out.scrap = ProgressionEngine.openingScrap
        var series = 0
        var match = 0
        var attempts = 0

        while !out.complete, out.wins.count < 40 {
            let rules = ProgressionEngine.scrapRules(seriesIndex: series)
            let breakdown = ScrapBreakdown(
                base: rules.base,
                damage: rules.damageFull / 2,
                survivor: rules.survivor,
                flawless: flawless ? rules.flawless : 0
            )
            let settled = ProgressionEngine.settle(
                seriesIndex: series, matchIndex: match, attempts: attempts, points: out.points,
                result: .win, breakdown: breakdown, isReplay: false,
                campaignComplete: out.complete, gates: .open)

            out.scrap += settled.scrap.total
            out.points = settled.pointsAfter
            if settled.finishedSeries { out.finals += 1 }
            out.complete = settled.campaignComplete
            series = settled.seriesIndex
            match = settled.matchIndex
            attempts = settled.attempts
            out.wins.append((ProgressionEngine.level(points: out.points).level, out.scrap, out.points))
        }
        return out
    }

    private static func checkCampaign() {
        let campaign = runCampaign()
        check("the campaign is twenty matches", campaign.wins.count == 20, detail: "\(campaign.wins.count)")
        check("five Series finals were won", campaign.finals == 5, detail: "\(campaign.finals)")
        check("the last final finishes the campaign", campaign.complete)
        check("Level 100 arrives on the last final with no flawless wins",
              campaign.wins.last?.level == 100 && campaign.wins.dropLast().allSatisfy { $0.level < 100 },
              detail: "\(campaign.wins.map(\.level))")
        check("the campaign pays exactly the cap in points",
              campaign.points == ProgressionEngine.maxPoints,
              detail: "\(campaign.points) of \(ProgressionEngine.maxPoints)")
        check("the Level bar never goes backwards",
              zip(campaign.wins, campaign.wins.dropFirst()).allSatisfy { $0.level <= $1.level })
        say("campaign: \(campaign.scrap) scrap in hand at the end, Level \(campaign.wins.last?.level ?? 0)")
        say("campaign Levels win by win: \(campaign.wins.map(\.level))")

        // Flawless all the way is the fast route, and it cannot overshoot the cap.
        let perfect = runCampaign(flawless: true)
        let firstCapped = perfect.wins.firstIndex { $0.level == 100 } ?? 99
        check("a flawless run reaches the cap before the last final",
              perfect.points == ProgressionEngine.maxPoints && firstCapped < 19,
              detail: "Level 100 on win \(firstCapped + 1)")
        check("a flawless run banks more scrap than a plain one", perfect.scrap > campaign.scrap)

        // Brief v5 section 9.1: the campaign can be replayed afterwards, and that is what keeps
        // the last few parts reachable.
        let replay = ProgressionEngine.settle(
            seriesIndex: 4, matchIndex: 0, attempts: 0, points: ProgressionEngine.maxPoints,
            result: .win, breakdown: ScrapBreakdown(base: 260, damage: 130, survivor: 130),
            isReplay: true, campaignComplete: true, gates: .open)
        check("a replay after the campaign still pays scrap", replay.scrap.total == 520)
        check("a replay cannot move the campaign on",
              replay.seriesIndex == 4 && replay.matchIndex == 0)

        checkAffordability(campaign)
    }

    /// The money question brief v5 turns on: can a player who wins everything afford the parts the
    /// ladder has just opened for them. The rule the contracts file sets is within two wins of
    /// reaching the Level.
    private static func checkAffordability(_ campaign: Campaign) {
        let named = ["saw", "reinforced", "tracks", "ram", "horizontal_spinner", "legs",
                     "shock_prod", "flamethrower", "reactive", "crusher", "hover", "tesla_arc",
                     "drill_lance", "titanium", "twin_saw", "napalm_cannon", "adaptive_tracks",
                     "overcharge_core", "vortex_spinner", "apex"]
        let held = Set(Catalogue.shared.allPartIDs)
        let owned = Set(ProgressionEngine.startingOwned)
        var checked = 0
        var worst = (id: "none", price: 0, purse: 0)

        for id in named where held.contains(id) && !owned.contains(id) {
            let required = ProgressionEngine.levelRequired(id)
            let price = ProgressionEngine.price(id)
            guard let reached = campaign.wins.firstIndex(where: { $0.level >= required }) else {
                check("Level \(required) is reachable in one campaign", false, detail: id)
                continue
            }
            let twoMore = min(reached + 2, campaign.wins.count - 1)
            let purse = campaign.wins[twoMore].scrap
            checked += 1
            check("\(id) is affordable within two wins of Level \(required)", purse >= price,
                  detail: "\(price) against \(purse) in hand")
            if price > worst.price { worst = (id, price, purse) }
        }
        check("the affordability rule was checked against real parts", checked > 0, detail: "\(checked)")
        say("affordability: \(checked) of the brief's parts are in the catalogue; dearest was \(worst.id) at \(worst.price) against \(worst.purse) in hand")

        // And the whole shop, cleared once, inside one campaign.
        let bill = Catalogue.shared.allPartIDs
            .filter { !owned.contains($0) }
            .map { ProgressionEngine.price($0) }
            .reduce(0, +)
        check("a won campaign can clear the whole shop",
              campaign.scrap >= bill, detail: "\(campaign.scrap) in hand against \(bill) of parts")
        say("the shop costs \(bill) scrap to clear; a won campaign banks \(campaign.scrap)")
    }

    // MARK: - Losing, retrying, replaying

    private static func checkLossAndRetry() {
        let full = ScrapBreakdown(base: 150, damage: 150, survivor: 75, flawless: 75)

        let loss = ProgressionEngine.settle(
            seriesIndex: 1, matchIndex: 2, attempts: 0, points: 900,
            result: .loss, breakdown: full, isReplay: false, campaignComplete: false, gates: .open)
        check("a loss banks no scrap", loss.scrap.total == 0)
        check("a loss pays no Level points", loss.levelPoints == 0 && loss.pointsAfter == 900)
        check("a loss leaves the campaign where it was",
              loss.seriesIndex == 1 && loss.matchIndex == 2)
        check("a loss bumps the attempt count", loss.attempts == 1)
        check("a loss has no rewards screen", loss.rewards == nil)
        check("a loss unlocks nothing", loss.newlyUnlocked.isEmpty && loss.newPaintJobs.isEmpty)

        let draw = ProgressionEngine.settle(
            seriesIndex: 1, matchIndex: 2, attempts: 3, points: 900,
            result: .draw, breakdown: full, isReplay: false, campaignComplete: false, gates: .open)
        check("a draw is settled the same way as a loss",
              draw.scrap.total == 0 && draw.attempts == 4 && draw.rewards == nil)

        let win = ProgressionEngine.settle(
            seriesIndex: 1, matchIndex: 2, attempts: 4, points: 900,
            result: .win, breakdown: full, isReplay: false, campaignComplete: false, gates: .open)
        check("a win resets the attempt count", win.attempts == 0)
        check("a win moves the match on", win.matchIndex == 3 && win.seriesIndex == 1)
        check("a win banks the whole breakdown", win.scrap.total == full.total)
        check("a win has a rewards screen", win.rewards != nil)
        check("the rewards screen carries both Levels",
              win.rewards?.levelBefore.points == 900 && win.rewards?.levelAfter.points == win.pointsAfter)
        check("a flawless win pays a quarter more points",
              win.levelPoints == Int((Double(ProgressionEngine.winPoints(seriesIndex: 1, flawless: false, replay: false)) * 1.25).rounded()),
              detail: "\(win.levelPoints)")

        let plain = ProgressionEngine.settle(
            seriesIndex: 1, matchIndex: 2, attempts: 0, points: 900,
            result: .win, breakdown: ScrapBreakdown(base: 150, damage: 40, survivor: 0, flawless: 0),
            isReplay: false, campaignComplete: false, gates: .open)
        check("a win that lost a part pays the plain points",
              plain.levelPoints == ProgressionEngine.winPoints(seriesIndex: 1, flawless: false, replay: false))

        // A replay pays half of both.
        check("a replay pays half the points",
              ProgressionEngine.winPoints(seriesIndex: 0, flawless: false, replay: true)
              == ProgressionEngine.winPoints(seriesIndex: 0, flawless: false, replay: false) / 2)
        let replayRules = ProgressionEngine.scrapRules(seriesIndex: 4, replay: true)
        let fullRules = ProgressionEngine.scrapRules(seriesIndex: 4)
        check("a replay's scrap rules are half of the Series'",
              replayRules.base == fullRules.base / 2
              && replayRules.damageFull == fullRules.damageFull / 2
              && replayRules.survivor == fullRules.survivor / 2
              && replayRules.flawless == fullRules.flawless / 2)
        check("a replay keeps the same survivor line",
              abs(replayRules.survivorMin - fullRules.survivorMin) < 0.0001)

        // Every attempt is a different fight, and it is the same opponent in the same arena.
        let state = sampleState(seriesIndex: 1, matchIndex: 1)
        guard let first = ProgressionEngine.nextMatch(state: state, gates: .open) else {
            check("there is a match to retry", false)
            return
        }
        let seedOne = first.seed(careerSeed: state.currentSeasonSeed)
        check("the same attempt is always the same fight",
              seedOne == first.seed(careerSeed: state.currentSeasonSeed))
        state.attempts = 1
        guard let second = ProgressionEngine.nextMatch(state: state, gates: .open) else {
            check("the retry has a match", false)
            return
        }
        check("every attempt is fought on a new seed",
              seedOne != second.seed(careerSeed: state.currentSeasonSeed))
        check("a retry is the same opponent in the same arena",
              first.opponent.id == second.opponent.id && first.arena == second.arena)
        check("a retry counts the attempts on the card", second.attempts == 1)
        check("a different career fights a different fight",
              seedOne != first.seed(careerSeed: state.currentSeasonSeed + 1))
    }

    // MARK: - The next match card

    private static func checkNextMatchCard() {
        let state = sampleState()
        var seen = 0

        for series in 0..<SeriesProgress.seriesCount {
            for match in 0..<SeriesProgress.matchesPerSeries {
                state.seriesIndex = series
                state.matchIndex = match
                guard let card = ProgressionEngine.nextMatch(state: state, gates: .open) else {
                    check("Series \(series + 1) match \(match + 1) has a card", false)
                    continue
                }
                seen += 1
                let name = "Series \(series + 1) match \(match + 1)"
                check("\(name) card knows where it is",
                      card.seriesIndex == series && card.matchIndex == match)
                check("\(name) card's arena exists", Catalogue.shared.arena(card.arena) != nil)
                check("\(name) card's arena is the Series' arena for that match",
                      card.arena == CareerCatalogue.shared.progression.series(series)?.arena(matchIndex: match))
                check("\(name) card carries the Series' scrap rules",
                      card.scrapRules == ProgressionEngine.scrapRules(seriesIndex: series))
                check("\(name) card says what a win pays",
                      card.winPoints == ProgressionEngine.winPoints(seriesIndex: series, flawless: false, replay: false)
                      && card.winPoints > 0)
                check("\(name) card names the house bot",
                      !card.houseBotID.isEmpty && !card.houseBotName.isEmpty && !card.houseBotLine.isEmpty)
                check("\(name) card carries the skill the arena is sent",
                      card.aiSkill == CareerTier.allCases[series].rawValue)
                check("\(name) card carries a legal temperament",
                      CareerEngine.temperaments.contains(card.temperament), detail: card.temperament)
                check("\(name) card has something to say about the opponent", !card.scoutingLine.isEmpty)
                check("\(name) card has no grudge line with no history", card.grudgeLine.isEmpty)
                check("\(name) card's opponent is a legal machine", BuildRules.isValid(card.opponent.spec),
                      detail: BuildRules.errors(card.opponent.spec).joined(separator: " "))
                check("\(name) card leaves no placeholder in the words",
                      !card.scoutingLine.contains("{player}") && !card.scoutingLine.contains("{bot}"))
                check("\(name) card is only the final if it is the fourth",
                      card.isFinal == (match == SeriesProgress.matchesPerSeries - 1))
                check("\(name) card is not a replay", !card.isReplay)
            }
        }
        check("every match of every Series has a card", seen == 20, detail: "\(seen)")

        state.seriesIndex = 4
        state.matchIndex = 3
        check("a final's title says so",
              ProgressionEngine.nextMatch(state: state, gates: .open)?.title == "Series 5 final",
              detail: ProgressionEngine.nextMatch(state: state, gates: .open)?.title ?? "none")
        state.matchIndex = 1
        check("a match's title is the Series and the match",
              ProgressionEngine.nextMatch(state: state, gates: .open)?.title == "Series 5, match 2",
              detail: ProgressionEngine.nextMatch(state: state, gates: .open)?.title ?? "none")
        state.matchIndex = SeriesProgress.matchesPerSeries
        check("a finished Series has no next match", ProgressionEngine.nextMatch(state: state, gates: .open) == nil)

        // The deterministic field: the same career always fields the same machines.
        let seed = sampleState().currentSeasonSeed
        check("the same career draws the same opponents",
              (0..<20).allSatisfy { index in
                  let series = index / 4, match = index % 4
                  return ProgressionEngine.opponent(seriesIndex: series, matchIndex: match, careerSeed: seed).name
                      == ProgressionEngine.opponent(seriesIndex: series, matchIndex: match, careerSeed: seed).name
              })
        check("a different career draws a different filler",
              ProgressionEngine.opponent(seriesIndex: 0, matchIndex: 0, careerSeed: 1).name
              != ProgressionEngine.opponent(seriesIndex: 0, matchIndex: 0, careerSeed: 777_777).name)
        check("a Series final is against the rival the catalogue names",
              ProgressionEngine.opponent(seriesIndex: 0, matchIndex: 3, careerSeed: 5).rivalID == "clatterbox")
        check("the store can find the rival before the card is built",
              ProgressionEngine.opponentRivalID(state: sampleState(seriesIndex: 0, matchIndex: 3)) == "clatterbox")
        check("a filler match names no rival",
              ProgressionEngine.opponentRivalID(state: sampleState(seriesIndex: 0, matchIndex: 0)).isEmpty)

        // The repair bill is a charge, so it has to reach the card.
        let bot = BotBuild(spec: .tinribs)
        bot.damageJSON = JSONText.string(from: [
            "wheels": [1.0, 0.5, 1.0, 1.0], "weapon": 0.4, "drive": 0.9, "core": 0.9,
            "armour": ["front": 0.3, "sides": 1.0, "rear": 1.0, "top": 1.0]
        ])
        let withBill = ProgressionEngine.nextMatch(state: sampleState(), playerBot: bot, gates: .open)
        check("a machine's outstanding repair bill is on the card",
              (withBill?.repairsDue ?? 0) > 0, detail: "\(withBill?.repairsDue ?? 0)")
        check("the card's repair bill is the garage's repair bill",
              withBill?.repairsDue == CareerEngine.repairBill(for: bot.spec, damage: bot.currentDamage).total)
        check("a pristine machine owes nothing",
              ProgressionEngine.nextMatch(state: sampleState(), playerBot: BotBuild(spec: .tinribs),
                                          gates: .open)?.repairsDue == 0)

        // A replay is the match being replayed, at half rates.
        let done = sampleState(seriesIndex: 4, matchIndex: SeriesProgress.matchesPerSeries)
        done.campaignComplete = true
        done.replaySeriesIndex = 0
        done.replayMatchIndex = 1
        guard let card = ProgressionEngine.nextMatch(state: done, gates: .open) else {
            check("a replay has a card", false)
            return
        }
        check("a replay's card is the match being replayed",
              card.seriesIndex == 0 && card.matchIndex == 1 && card.isReplay)
        check("a replay's card pays the replay rate",
              card.winPoints == ProgressionEngine.winPoints(seriesIndex: 0, flawless: false, replay: true))
        check("a replay's card carries the replay scrap rules",
              card.scrapRules == ProgressionEngine.scrapRules(seriesIndex: 0, replay: true))
    }

    // MARK: - The Series strip

    private static func checkSeriesSlots() {
        let state = sampleState(seriesIndex: 1, matchIndex: 2)

        let earlier = ProgressionEngine.seriesSlots(state: state, seriesIndex: 0)
        check("an earlier Series is all won", earlier.count == 4 && earlier.allSatisfy { $0.state == .won })

        let current = ProgressionEngine.seriesSlots(state: state, seriesIndex: 1)
        check("the matches already won say won",
              current.count == 4 && current[0].state == .won && current[1].state == .won)
        check("the match on duty says next", current[2].state == .next)
        check("the matches after it are locked", current[3].state == .locked)
        check("only the fourth slot is the final", current.map(\.isFinal) == [false, false, false, true])
        check("every slot names its opponent and its livery",
              current.allSatisfy { !$0.opponentName.isEmpty && $0.opponentLiveryHex.hasPrefix("#") })
        check("the slots are in order", current.map(\.index) == [0, 1, 2, 3])
        check("a slot with nothing in the log carries no note",
              current.allSatisfy { $0.note.isEmpty })

        let later = ProgressionEngine.seriesSlots(state: state, seriesIndex: 3)
        check("a later Series is locked", later.allSatisfy { $0.state == .locked })

        // The note comes from the fight log.
        let log = FightLog()
        log.tier = .regional
        log.round = 0
        log.didWin = true
        log.outcome = "ko"
        log.atSeconds = 34
        let noted = ProgressionEngine.seriesSlots(state: state, seriesIndex: 1, logs: [log])
        check("a won slot carries the note the log remembers",
              noted[0].note == "Knockout at 34 s", detail: noted[0].note)
        check("a slot the log knows nothing about stays blank", noted[1].note.isEmpty)
        check("a ladder fight is not mistaken for a Series match",
              ProgressionEngine.note(for: [ladderLog()], tier: "regional", round: 0).isEmpty)
        check("the notes are plain words",
              ["ko", "out_of_arena", "component_kill", "judges", "timeout", "forfeit"].allSatisfy {
                  let text = ProgressionEngine.note(outcome: $0, atSeconds: 61)
                  return !text.isEmpty && !text.contains("_") && !text.contains("\u{2014}")
              })

        // After the campaign every won match can be fought again.
        let done = sampleState(seriesIndex: 4, matchIndex: SeriesProgress.matchesPerSeries)
        done.campaignComplete = true
        check("after the campaign the whole Series can be replayed",
              ProgressionEngine.seriesSlots(state: done, seriesIndex: 2).allSatisfy { $0.state == .replayable })
        check("replays are available once the campaign is won",
              ProgressionEngine.replaysAvailable(state: done, gates: .open))
        check("replays are not available part way through",
              !ProgressionEngine.replaysAvailable(state: state, gates: .open))

        // The free half: winning the Series 2 final leaves the player at the wall, and replaying
        // what they have won is the only way left to earn, so it has to be open.
        let walled = sampleState(seriesIndex: 1, matchIndex: SeriesProgress.matchesPerSeries)
        check("the wall opens replays so a free player can still earn",
              ProgressionEngine.replaysAvailable(state: walled, gates: Gates(isUnlocked: false)))
        check("a bought game at the same point is simply moved on instead",
              !ProgressionEngine.replaysAvailable(state: walled, gates: .open))
        check("a match already won can be replayed",
              ProgressionEngine.isWon(state: walled, seriesIndex: 0, matchIndex: 2)
              && ProgressionEngine.isWon(state: walled, seriesIndex: 1, matchIndex: 3))
        check("a match never fought cannot be replayed",
              !ProgressionEngine.isWon(state: state, seriesIndex: 1, matchIndex: 2)
              && !ProgressionEngine.isWon(state: state, seriesIndex: 4, matchIndex: 0))
    }

    // MARK: - The match report

    /// Wave B judges: a decision on the cards carries the card and says why in words; a
    /// knockout carries none.
    private static func checkJudgesCard(knockout: MatchReport) {
        check("a knockout report carries no judges' card", knockout.judges == nil)
        let decision: [String: Any] = [
            "outcome": ["type": "judges", "winner": "player-1", "loser": "ai-1", "at_s": 180],
            "judges": ["player-1": ["damage": 4.5, "control": 0, "aggression": 1.2],
                       "ai-1": ["damage": 0.5, "control": 3, "aggression": 0.8]],
            "judges_detail": ["player-1": ["lost_pct": 14, "parts_out": 0, "control_s": 0, "payoffs": 0,
                                           "payoff_s": 0, "aggression_s": 36, "blows": 0],
                              "ai-1": ["lost_pct": 20, "parts_out": 1, "control_s": 21, "payoffs": 0,
                                       "payoff_s": 0, "aggression_s": 27, "blows": 0]],
            "parts_lost": ["ai-1": [["part": "weapon", "label": "Weapon", "state": "destroyed"]]]
        ]
        let result = FightResult(object: decision)
        guard let card = JudgesCard.make(result: result, myID: "player-1", myName: "Tinribs",
                                         theirName: "Penny Dread") else {
            check("a judges' result makes a card", false)
            return
        }
        check("the card totals each machine's columns", abs(card.myTotal - 5.7) < 0.001 && abs(card.theirTotal - 4.3) < 0.001,
              detail: "\(card.myTotal) \(card.theirTotal)")
        check("the verdict reads in words", card.verdict == "Tinribs wins on the cards, 5.7 to 4.3.", detail: card.verdict)
        check("the damage line names the weapon it lost",
              card.reasons.first == "Tinribs lost 14% of its machine. Penny Dread lost 20% of its machine, and its weapon.",
              detail: card.reasons.first ?? "none")
        check("the control line says who held whom",
              card.reasons.count == 3 && card.reasons[1] == "Penny Dread had Tinribs on its back, in the air or on the spikes for 21 s.",
              detail: card.reasons.count > 1 ? card.reasons[1] : "none")
        check("no em dashes on the card", !(card.reasons + [card.verdict]).joined().contains("\u{2014}"))
    }

    private static func checkMatchReport() {
        let report = ProgressionEngine.matchReport(
            result: FightResult(json: resultV2), spec: .tinribs, startDamage: nil,
            botName: "Tinribs", opponentName: "Clatterbox", resultJSON: resultV2)

        check("a won match reads as a win", report.isWin && report.result == .win)
        check("the report keeps the outcome and the clock",
              report.outcome == "ko" && abs(report.durationSeconds - 74) < 0.001)
        check("the clock is printed as minutes and seconds", report.durationText == "1:14",
              detail: report.durationText)
        check("the report counts hits landed and taken",
              report.hitsLanded == 12 && report.hitsTaken == 5)
        check("the report carries the arena's scrap breakdown",
              report.scrap?.total == 270 && report.scrap?.isFlawless == true)
        check("the report names what was destroyed", report.partsLost == ["Rear right wheel"],
              detail: report.partsLost.joined(separator: ", "))
        check("the report names both machines",
              report.botName == "Tinribs" && report.opponentName == "Clatterbox")

        let labels = report.parts.map(\.label)
        check("there is one row per part with a condition", report.parts.count == 11,
              detail: "\(report.parts.count): \(labels.joined(separator: ", "))")
        check("the weapon is named first", labels.first == "Flipper", detail: labels.first ?? "none")
        check("the wheels are named by position",
              labels.contains("Front left wheel") && labels.contains("Rear right wheel"))
        check("the plates are named by face",
              labels.contains("Front armour") && labels.contains("Top armour"))
        check("every row is labelled in words for a player",
              report.parts.allSatisfy { !$0.label.isEmpty && !$0.label.contains("_") })
        check("the conditions are the arena's own numbers",
              report.parts.first { $0.label == "Front armour" }?.percent == 30,
              detail: "\(report.parts.first { $0.label == "Front armour" }?.percent ?? -1)")
        check("a destroyed part reads as destroyed",
              report.parts.first { $0.label == "Rear right wheel" }?.destroyed == true)
        checkJudgesCard(knockout: report)
        check("the report knows what the machine went in with",
              report.parts.allSatisfy { $0.startCondition == 1 })

        // A result with none of the v2 blocks still makes a report.
        let plain = ProgressionEngine.matchReport(
            result: FightResult(json: resultV1), spec: .tinribs, startDamage: nil,
            botName: "Tinribs", opponentName: "Clatterbox", resultJSON: resultV1)
        check("a result with no v2 blocks still reads as a win", plain.isWin)
        check("a result with no hits block counts no hits",
              plain.hitsLanded == 0 && plain.hitsTaken == 0)
        check("a result with no breakdown says so rather than inventing one", plain.scrap == nil)
        check("a result with no parts_lost works it out from the conditions",
              plain.partsLost == ["Rear right wheel"], detail: plain.partsLost.joined(separator: ", "))

        // A loss, and a fight that never came back at all.
        let loss = ProgressionEngine.matchReport(
            result: FightResult(json: lostResult), spec: .tinribs, startDamage: nil,
            botName: "Tinribs", opponentName: "Clatterbox", resultJSON: lostResult)
        check("a lost match reads as a loss", loss.result == .loss && !loss.isWin)

        var carried = FightResult.BotDamage()
        carried.wheels = [1, 0.5, 1, 1]
        carried.weapon = 0.4
        let forfeit = ProgressionEngine.matchReport(
            result: nil, spec: .tinribs, startDamage: carried,
            botName: "Tinribs", opponentName: "Clatterbox")
        check("no result at all is a forfeit loss",
              forfeit.result == .loss && forfeit.outcome == "forfeit")
        check("a forfeit still shows the machine's condition",
              forfeit.parts.count == 11 && forfeit.parts.first?.percent == 40,
              detail: "\(forfeit.parts.count) rows, first at \(forfeit.parts.first?.percent ?? -1)")
        check("a forfeit banks nothing", forfeit.scrap == nil)

        // Tracks report one condition per side, and a six wheeler has six.
        var tracked = BuildSpec.tinribs
        tracked.drive = "tracks"
        var trackDamage = FightResult.BotDamage()
        trackDamage.wheels = [1, 0.5]
        let trackReport = ProgressionEngine.partConditions(spec: tracked, damage: trackDamage, start: nil)
        check("a tracked machine reports its two sides",
              trackReport.map(\.label).contains("Left track")
              && trackReport.map(\.label).contains("Right track"))
        check("six wheels are named front, middle and rear",
              ProgressionEngine.wheelLabels(count: 6, isTracked: false)
              == ["Front left wheel", "Front right wheel", "Middle left wheel",
                  "Middle right wheel", "Rear left wheel", "Rear right wheel"])
        check("two wheels are just left and right",
              ProgressionEngine.wheelLabels(count: 2, isTracked: false) == ["Left wheel", "Right wheel"])

        // The v2 blocks on their own, decoded.
        let extras = ProgressionEngine.ResultExtras.parse(resultV2)
        check("the v2 blocks decode", !extras.isEmpty)
        check("the start condition block decodes",
              extras.conditionStart[ProgressionEngine.playerID]?.wheels.count == 4)
        check("the parts lost block keeps the arena's own words",
              extras.partsLost[ProgressionEngine.playerID]?.first?.state == "destroyed")
        check("a breakdown adds up to its total",
              extras.scrap[ProgressionEngine.playerID]?.total == 270)
        check("nonsense text decodes to nothing rather than crashing",
              ProgressionEngine.ResultExtras.parse("not json at all").isEmpty)
        check("an empty string decodes to nothing",
              ProgressionEngine.ResultExtras.parse("").isEmpty)

        #if !HARNESS
        check("the engine and the fight config agree which bot is the player",
              ProgressionEngine.playerID == CareerFightConfig.playerID)
        #endif
    }

    // MARK: - The shop

    private static func checkShop() {
        let state = sampleState(points: ProgressionEngine.points(forLevel: 40), scrap: 5_000)
        let entries = ProgressionEngine.shopEntries(state: state, gates: .open)

        check("the shop covers every part in the catalogue",
              entries.count == Catalogue.shared.allPartIDs.count,
              detail: "\(entries.count) of \(Catalogue.shared.allPartIDs.count)")
        check("no part is in the shop twice", Set(entries.map(\.id)).count == entries.count)
        check("every row has a name, a weight, a price and a Level",
              entries.allSatisfy { !$0.name.isEmpty && $0.weight > 0 && $0.price > 0 && $0.levelRequired >= 1 })
        check("every row has something to say about the part",
              entries.allSatisfy { !$0.blurb.isEmpty })
        check("the five kinds are all in the shop",
              Set(entries.map(\.category)).count == ShopEntry.Category.allCases.count)

        // Grouped by kind, and in ladder order inside each kind.
        let order = ShopEntry.Category.allCases
        let groups = entries.map { order.firstIndex(of: $0.category) ?? 0 }
        check("the shop is grouped by kind", zip(groups, groups.dropFirst()).allSatisfy { $0 <= $1 })
        var ordered = true
        for category in order {
            let levels = entries.filter { $0.category == category }.map(\.levelRequired)
            if !zip(levels, levels.dropFirst()).allSatisfy({ $0 <= $1 }) { ordered = false }
        }
        check("each kind is in ladder order", ordered)

        check("what the player owns says owned",
              entries.filter { state.blueprints.contains($0.id) }.allSatisfy(\.isOwned))
        check("a part above the player's Level says which Level",
              entries.first { $0.id == "crusher" }?.availability == .needsLevel(50))
        check("a part at the player's Level and affordable can be bought",
              entries.first { $0.id == "horizontal_spinner" }?.availability == .buyable)

        let poor = sampleState(points: ProgressionEngine.points(forLevel: 40), scrap: 0)
        check("a part the player cannot afford says so",
              ProgressionEngine.shopEntries(state: poor, gates: .open)
                  .first { $0.id == "horizontal_spinner" }?.availability == .tooPoor)

        // The wall. A free player can reach Level 33 and no further, so everything above the free
        // Level cap is behind the wall, and everything at or below it is not.
        let locked = Gates(isUnlocked: false)
        let free = ProgressionEngine.shopEntries(state: state, gates: locked)
        let cap = CareerCatalogue.shared.progression.freeLevelCap
        check("the free game cannot buy above its Level cap",
              free.allSatisfy { $0.isOwned || $0.levelRequired <= cap || $0.availability == .behindWall },
              detail: free.filter { !$0.isOwned && $0.levelRequired > cap && $0.availability != .behindWall }
                  .map(\.id).joined(separator: ", "))
        check("nothing inside the free Level cap is walled off",
              free.filter { $0.levelRequired <= cap }.allSatisfy { $0.availability != .behindWall },
              detail: free.filter { $0.levelRequired <= cap && $0.availability == .behindWall }
                  .map(\.id).joined(separator: ", "))
        check("a part the player already owns is never walled off",
              free.filter { state.blueprints.contains($0.id) }.allSatisfy(\.isOwned))
        check("the wall says what opens it in plain words",
              locked.lockedReason(.part("crusher")).contains("full game"))

        // One answer to "can I buy this", so the row and the store cannot disagree.
        check("the availability of a row is the availability the store checks",
              entries.allSatisfy {
                  $0.availability == ProgressionEngine.availability($0.id, state: state, gates: .open)
              })
        check("an owned part is never buyable twice",
              ProgressionEngine.availability("flipper", state: state, gates: .open) == .owned)
    }

    private static func checkPaintJobs() {
        let jobs = ProgressionEngine.paintJobs(level: 1)
        check("ten paint jobs ship", jobs.count == 10, detail: "\(jobs.count)")
        check("they are one every ten Levels",
              jobs.map(\.level) == Array(stride(from: 10, through: 100, by: 10)))
        check("every paint job has an id and a name",
              jobs.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
        check("no paint job is unlocked at Level 1", jobs.allSatisfy { !$0.unlocked })
        check("Level 50 has unlocked five of them",
              ProgressionEngine.paintJobs(level: 50).filter(\.unlocked).count == 5)
        check("Level 100 has unlocked all of them",
              ProgressionEngine.paintJobs(level: 100).allSatisfy(\.unlocked))
        check("a milestone is reached exactly once",
              ProgressionEngine.newPaintJobs(from: 19, to: 21) == ["paint_racing"])
        check("two milestones in one jump are both handed over",
              ProgressionEngine.newPaintJobs(from: 9, to: 20).count == 2)
        check("standing still hands over nothing",
              ProgressionEngine.newPaintJobs(from: 20, to: 20).isEmpty)

        // The win that crosses a Level hands over the parts and the paint at once.
        let crossing = ProgressionEngine.settle(
            seriesIndex: 0, matchIndex: 1, attempts: 0,
            points: ProgressionEngine.points(forLevel: 9) + 90,
            result: .win, breakdown: ScrapBreakdown(base: 90, damage: 45, survivor: 45),
            isReplay: false, campaignComplete: false, gates: .open)
        check("a win that crosses Level 10 hands over that paint job",
              crossing.newPaintJobs.contains("paint_hazard"),
              detail: crossing.newPaintJobs.joined(separator: ", "))
        check("a win that crosses a Level says what it unlocked", !crossing.newlyUnlocked.isEmpty)
        check("a paint job already seen is not announced again",
              !ProgressionEngine.settle(
                  seriesIndex: 0, matchIndex: 1, attempts: 0,
                  points: ProgressionEngine.points(forLevel: 9) + 90,
                  paintSeen: ["paint_hazard"],
                  result: .win, breakdown: ScrapBreakdown(base: 90),
                  isReplay: false, campaignComplete: false, gates: .open)
                  .newPaintJobs.contains("paint_hazard"))
        check("what a Level unlocks is in ladder order",
              ProgressionEngine.newlyUnlocked(from: 1, to: 20)
              == ProgressionEngine.newlyUnlocked(from: 1, to: 20)
                  .sorted { ProgressionEngine.levelRequired($0) < ProgressionEngine.levelRequired($1) })
        check("a part not in the catalogue yet is never announced as unlocked",
              ProgressionEngine.newlyUnlocked(from: 1, to: 100)
                  .allSatisfy { Catalogue.shared.allPartIDs.contains($0) })

        // Bug 5 (docs/aaa/frontend-meta.md): a part the player owns is never "new in the shop".
        let starting = ProgressionEngine.startingOwned
        let ownedAnnounced = ProgressionEngine.newlyUnlocked(from: 1, to: 100, owned: starting)
            .filter { starting.contains($0) }
        check("the rewards screen never announces a part the player already owns",
              ownedAnnounced.isEmpty, detail: ownedAnnounced.joined(separator: ", "))
        let startingOnLadder = ProgressionEngine.newlyUnlocked(from: 1, to: 100)
            .filter { starting.contains($0) }
        if !startingOnLadder.isEmpty {
            // The shipped loadout owns rungs of the ladder (spare battery, saw, polycarbonate, ram,
            // titanium). The settle path has to leave every one of them out.
            var said: [String] = []
            var points = 0
            for series in 0..<SeriesProgress.seriesCount {
                for match in 0..<SeriesProgress.matchesPerSeries {
                    let won = ProgressionEngine.settle(
                        seriesIndex: series, matchIndex: match, attempts: 0, points: points,
                        owned: starting, result: .win, breakdown: ScrapBreakdown(base: 100),
                        isReplay: false, campaignComplete: false, gates: .open)
                    said.append(contentsOf: won.newlyUnlocked)
                    points = won.pointsAfter
                }
            }
            let lies = said.filter { starting.contains($0) }
            check("a whole campaign never announces the starting loadout as new",
                  lies.isEmpty, detail: lies.joined(separator: ", "))
            check("and it still announces the parts the player does not own",
                  !said.isEmpty && said.count == Set(said).count)
        }
        let bought = ProgressionEngine.newlyUnlocked(from: 1, to: 20, owned: ["pyramid"])
        check("a part bought early is not announced when its Level arrives", !bought.contains("pyramid"))
    }

    // MARK: - Old saves (brief v5 section 9.6)

    private static func checkMigration() {
        let old = CareerState(tier: .national, scrap: 700, seed: 99)
        // What a career saved before wave P looks like when it is read back: the new fields at
        // their defaults, the old ones full.
        old.migratedToSeries = false
        old.seriesIndex = 0
        old.matchIndex = 0
        old.levelPoints = 0
        old.wins = 7
        old.fightsPlayed = 11
        old.winsThisTier = 2
        old.blueprints = ["wedge", "flipper", "steel"]
        var bracket = CareerEngine.startSeason(
            tier: .national, seed: 99, player: samplePlayer(), rivals: CareerCatalogue.shared.rivals)
        bracket = CareerEngine.settlePlayerMatch(bracket, playerWon: true, note: "Knockout")
        bracket = CareerEngine.settlePlayerMatch(bracket, playerWon: true, note: "Knockout")
        old.bracket = bracket

        check("an old save is migrated on first read", ProgressionEngine.migrate(old))
        check("the circuit becomes the Series", old.seriesIndex == 2 && old.tier == .national)
        check("the ties already won become the match index", old.matchIndex == 2, detail: "\(old.matchIndex)")
        check("lifetime wins become Level points at Series 1 rates",
              old.levelPoints == 7 * (CareerCatalogue.shared.progression.series(0)?.winPoints ?? 0),
              detail: "\(old.levelPoints)")
        check("the migrated career is at the Level those points buy",
              old.level == ProgressionEngine.level(points: old.levelPoints).level)
        check("scrap survives migration", old.scrap == 700)
        check("owned parts survive migration", old.blueprints.contains("flipper"))
        check("the starting loadout is owned whatever the old save held",
              ProgressionEngine.startingOwned.allSatisfy { old.blueprints.contains($0) })
        check("a migrated career is not replaying anything", !old.isReplaying)
        check("a migrated career has no attempts against it", old.attempts == 0)
        check("migration never runs twice", !ProgressionEngine.migrate(old))
        check("a career started after wave P is never migrated",
              !ProgressionEngine.migrate(CareerState(tier: .scrapyard, scrap: 300, seed: 1)))

        // An old save with no bracket at all falls back to the win count it does have.
        let noBracket = CareerState(tier: .regional, scrap: 120, seed: 5)
        noBracket.migratedToSeries = false
        noBracket.seriesIndex = 0
        noBracket.winsThisTier = 3
        noBracket.wins = 3
        ProgressionEngine.migrate(noBracket)
        check("an old save with no season still lands somewhere sensible",
              noBracket.seriesIndex == 1 && noBracket.matchIndex == 3)
        check("the match index never runs off the end of a Series",
              noBracket.matchIndex < SeriesProgress.matchesPerSeries)

        // A save that had won the lot.
        let champion = CareerState(tier: .masters, scrap: 4_000, seed: 7)
        champion.migratedToSeries = false
        champion.championshipsWon = 1
        champion.wins = 40
        ProgressionEngine.migrate(champion)
        check("a career that had won everything can replay", champion.campaignComplete)
        check("a migrated Level never goes past the cap",
              champion.levelPoints <= ProgressionEngine.maxPoints && champion.level == 100)
    }

    // MARK: - Rivals

    /// Wave D, the three grudge bugs (docs/aaa/decisions-2026-09-30.md).
    /// (a) `{player}` is the PLAYER's name, never the rival's own roboteer;
    /// (b) line 1 is "they beat you last time", line 2 "you beat them", for every rival (Clatterbox
    ///     and Penny Dread had them the wrong way round);
    /// (c) line 0, the first meeting, reaches the card before the two have ever met.
    private static func checkGrudgeWords() {
        let rivals = CareerCatalogue.shared.rivals
        let me = "Sam Tester"
        for rival in rivals {
            check("\(rival.name) has three grudge lines in the order the code reads them", rival.grudgeLines.count == 3)
            guard rival.grudgeLines.count == 3 else { continue }
            // (b) Who acted is the first word: the rival's side when they won, the player's when the
            // player did. Line 1 never opens on the player; line 2 always does.
            let playerOpeners = ["You ", "{bot} ", "{player} "]
            let they = rival.grudgeLines[1]
            let you = rival.grudgeLines[2]
            check("\(rival.name) line 1 is about THEM beating you",
                  !playerOpeners.contains { they.hasPrefix($0) }, detail: they)
            check("\(rival.name) line 2 is about YOU beating them",
                  playerOpeners.contains { you.hasPrefix($0) }, detail: you)
            // (a) Every line, at every stage of the history, calls the player by the player's name.
            for (index, template) in rival.grudgeLines.enumerated() {
                let record = RivalRecord(
                    rivalID: rival.id, name: rival.name, roboteer: rival.roboteer,
                    liveryHex: rival.liveryHex, spec: rival.spec, tier: .scrapyard,
                    grudgeLines: rival.grudgeLines)
                record.winsVsPlayer = index == 1 ? 1 : 0
                record.lossesVsPlayer = index == 2 ? 1 : 0
                record.lastResultWasTheirs = index == 1
                let said = record.grudgeLine(botName: "Tinribs", playerName: me)
                let expected = CareerEngine.sentenceStarts(template
                    .replacingOccurrences(of: "{player}", with: me)
                    .replacingOccurrences(of: "{bot}", with: "Tinribs"))
                check("\(rival.name) line \(index) is the one said at that point in the history",
                      said == expected, detail: said)
                if template.contains("{player}") {
                    let theirs = template.components(separatedBy: rival.roboteer).count
                    check("\(rival.name) line \(index) names the player, not \(rival.roboteer)",
                          said.contains(me) && said.components(separatedBy: rival.roboteer).count == theirs,
                          detail: said)
                }
            }
        }
        if let clatterbox = rivals.first(where: { $0.id == "clatterbox" }),
           let penny = rivals.first(where: { $0.id == "penny_dread" }), clatterbox.grudgeLines.count == 3,
           penny.grudgeLines.count == 3 {
            check("Clatterbox: the flip is the line for when YOU won",
                  clatterbox.grudgeLines[2].contains("on its back") && !clatterbox.grudgeLines[1].contains("on its back"))
            check("Penny Dread: Hal's flip is the line for when THEY won",
                  penny.grudgeLines[1].contains("flipped {bot}") && penny.grudgeLines[2].contains("threw Penny Dread"))
        } else {
            check("Clatterbox and Penny Dread are in the catalogue", false)
        }

        // (c) A rival with a record but no history yet says line 0 on the card.
        if let rival = rivals.first {
            let fresh = RivalRecord(
                rivalID: rival.id, name: rival.name, roboteer: rival.roboteer,
                liveryHex: rival.liveryHex, spec: rival.spec, tier: .scrapyard,
                grudgeLines: rival.grudgeLines)
            let entrant = CareerEntrant(
                id: rival.id, name: rival.name, roboteer: rival.roboteer, liveryHex: rival.liveryHex,
                kind: .rival, spec: rival.spec, rivalID: rival.id)
            let opener = ProgressionEngine.grudgeLine(for: entrant, record: fresh, playerBotName: "Tinribs",
                                                      playerName: me)
            check("a first meeting shows the rival's first-meeting line on the card",
                  !opener.isEmpty && opener == fresh.grudgeLine(botName: "Tinribs", playerName: me), detail: opener)
        }

        // With no Game Center name the player is "your team", capitalised when it opens a sentence.
        let defaults = UserDefaults(suiteName: "roboteer.selftest.grudge") ?? .standard
        defaults.removeObject(forKey: CareerEngine.playerNameKey)
        check("with no name the player is 'your team'", CareerEngine.playerName(defaults) == "your team")
        check("and a sentence that opens on it reads 'Your team'",
              CareerEngine.grudgeLine(lines: ["{player} beat Cold Snap on the judges."], wins: 0, losses: 0,
                                      theyWonLast: false, playerName: "your team", botName: "Tinribs")
              == "Your team beat Cold Snap on the judges.")
        defaults.set("Mika", forKey: CareerEngine.playerNameKey)
        check("a signed-in player is called by their name", CareerEngine.playerName(defaults) == "Mika")
        defaults.removeObject(forKey: CareerEngine.playerNameKey)
    }

    private static func checkRivalMemory() {
        guard let rival = CareerCatalogue.shared.rivals.first else {
            check("there is a rival to remember", false)
            return
        }
        let cold = CareerEngine.grudgeLine(lines: rival.grudgeLines, wins: 0, losses: 0,
                                           theyWonLast: false, playerName: "Dot", botName: "Tinribs")
        let beaten = CareerEngine.grudgeLine(lines: rival.grudgeLines, wins: 1, losses: 0,
                                             theyWonLast: true, playerName: "Dot", botName: "Tinribs")
        let beat = CareerEngine.grudgeLine(lines: rival.grudgeLines, wins: 0, losses: 1,
                                           theyWonLast: false, playerName: "Dot", botName: "Tinribs")
        let expected = rival.grudgeLines[0]
            .replacingOccurrences(of: "{player}", with: "Dot")
            .replacingOccurrences(of: "{bot}", with: "Tinribs")
        check("a rival you have never met says the first line", cold == expected)
        check("a rival who beat you says something else", beaten != cold)
        check("a rival you beat says something else again", beat != cold && beat != beaten)
        check("no placeholder survives into the line",
              ![cold, beaten, beat].contains { $0.contains("{player}") || $0.contains("{bot}") })

        let start = rival.spec
        let masters = CareerEngine.rivalSpec(rival, at: .masters)
        check("a rival's machine changes as it climbs", masters != start)
        check("a rival keeps its own name and livery",
              masters.name == rival.name && masters.liveryHex == rival.liveryHex)

        // The grudge line only reaches a card when the record is that rival's own.
        let record = RivalRecord(
            rivalID: rival.id, name: rival.name, roboteer: rival.roboteer,
            liveryHex: rival.liveryHex, spec: rival.spec, tier: .scrapyard,
            grudgeLines: rival.grudgeLines)
        record.winsVsPlayer = 1
        record.lastResultWasTheirs = true
        let entrant = CareerEntrant(
            id: rival.id, name: rival.name, roboteer: rival.roboteer, liveryHex: rival.liveryHex,
            kind: .rival, spec: rival.spec, rivalID: rival.id)
        check("a rival with history has something to say",
              !ProgressionEngine.grudgeLine(for: entrant, record: record, playerBotName: "Tinribs").isEmpty)
        let other = CareerEntrant(
            id: "filler-0", name: "Anyone", roboteer: "Nobody", liveryHex: "#5c6470",
            kind: .filler, spec: .defaultWedge)
        check("another machine's record is never read onto a filler",
              ProgressionEngine.grudgeLine(for: other, record: record, playerBotName: "Tinribs").isEmpty)
        checkGrudgeWords()

        // Bug 7 (docs/aaa/frontend-meta.md): a draw is not the rival's win.
        let met = RivalRecord(
            rivalID: rival.id, name: rival.name, roboteer: rival.roboteer,
            liveryHex: rival.liveryHex, spec: rival.spec, tier: .scrapyard,
            grudgeLines: rival.grudgeLines)
        ProgressionEngine.remember(.draw, in: met)
        check("a draw goes on neither side of a rival's record",
              met.winsVsPlayer == 0 && met.lossesVsPlayer == 0 && !met.lastResultWasTheirs)
        ProgressionEngine.remember(.loss, in: met)
        check("a loss is the rival's win", met.winsVsPlayer == 1 && met.lastResultWasTheirs)
        ProgressionEngine.remember(.draw, in: met)
        check("a draw after a loss stops the rival gloating over the last meeting",
              met.winsVsPlayer == 1 && met.lossesVsPlayer == 0 && !met.lastResultWasTheirs)
        ProgressionEngine.remember(.win, in: met)
        check("a win is the rival's loss", met.lossesVsPlayer == 1 && met.winsVsPlayer == 1)

        check("a filler is scouted off its own build",
              ProgressionEngine.scoutingLine(for: other).contains("Nobody has written anything"))
    }

    // MARK: - The wall

    /// The one rule the free half turns on: winning the Series 2 final while the game is locked
    /// keeps the player in Series 2 and offers the unlock once.
    private static func checkTheWall() {
        let locked = Gates(isUnlocked: false)
        let open = Gates(isUnlocked: true)

        let regionalLocked = CareerEngine.tierWon(at: .regional, gates: locked)
        check("a locked Series 2 final does not advance", regionalLocked.advancedTo == nil)
        check("a locked Series 2 final is a wall and not a loss", regionalLocked.hitTheWall)
        check("the wall names both Series and the full game in plain words",
              regionalLocked.sentence.contains("Series 2")
              && regionalLocked.sentence.contains("Series 3")
              && regionalLocked.sentence.contains(CareerTier.national.title)
              && regionalLocked.sentence.contains("full game"),
              detail: regionalLocked.sentence)
        check("no em dash reaches the player",
              !regionalLocked.sentence.contains("\u{2014}") && !regionalLocked.sentence.contains("\u{2013}"))
        check("the Series 1 final still advances while the game is locked",
              CareerEngine.tierWon(at: .scrapyard, gates: locked).advancedTo == .regional)
        check("the free half is exactly Series 1 and 2",
              locked.tierAvailable(.scrapyard) && locked.tierAvailable(.regional)
              && !locked.tierAvailable(.national) && !locked.tierAvailable(.championship)
              && !locked.tierAvailable(.masters))
        check("the locked half reaches The Yard and The Grinder and no further",
              locked.arenaAvailable("yard") && locked.arenaAvailable("grinder")
              && !locked.arenaAvailable("drop_zone") && !locked.arenaAvailable("furnace")
              && !locked.arenaAvailable("crush") && !locked.arenaAvailable("coliseum"))
        check("a locked arena says what opens it",
              locked.lockedReason(.arena("furnace")).contains("full game"))
        check("a locked Series says what opens it",
              locked.lockedReason(.tier(.national)).contains("full game"))

        // The same rule, through the engine that actually settles the match.
        let walled = ProgressionEngine.settle(
            seriesIndex: 1, matchIndex: 3, attempts: 0, points: 3_100,
            result: .win, breakdown: ScrapBreakdown(base: 150, damage: 75, survivor: 75),
            isReplay: false, campaignComplete: false, gates: locked)
        check("winning the Series 2 final while locked keeps the player in Series 2",
              walled.seriesIndex == 1 && walled.hitTheWall && walled.rewards?.hitTheWall == true)
        check("the walled win still pays its scrap and its points",
              walled.scrap.total == 300 && walled.levelPoints > 0)
        check("the walled Series reads as complete",
              walled.matchIndex == SeriesProgress.matchesPerSeries)

        let bought = ProgressionEngine.settle(
            seriesIndex: 1, matchIndex: 3, attempts: 0, points: 3_100,
            result: .win, breakdown: ScrapBreakdown(base: 150, damage: 75, survivor: 75),
            isReplay: false, campaignComplete: false, gates: open)
        check("winning the Series 2 final with the game bought opens Series 3",
              bought.seriesIndex == 2 && bought.matchIndex == 0 && !bought.hitTheWall)

        // Bug 1 (docs/aaa/frontend-meta.md): locked, walled, THEN bought. The walled save stood at
        // Series 2, match index 4 with no match and no replay; buying must carry it on.
        check("a walled save stays put while the game is still locked",
              ProgressionEngine.openedWallAdvance(seriesIndex: walled.seriesIndex, matchIndex: walled.matchIndex,
                                                  campaignComplete: false, gates: locked) == nil)
        let carried = ProgressionEngine.openedWallAdvance(
            seriesIndex: walled.seriesIndex, matchIndex: walled.matchIndex,
            campaignComplete: false, gates: open)
        check("a walled save moves to Series 3, match 1 once the game is bought",
              carried?.seriesIndex == 2 && carried?.matchIndex == 0)
        let walledSave = sampleState(seriesIndex: walled.seriesIndex, matchIndex: walled.matchIndex,
                                     points: walled.pointsAfter)
        walledSave.attempts = 2
        walledSave.replaySeriesIndex = 1
        walledSave.replayMatchIndex = 2
        check("the walled save has no match of its own while locked (the dead end, before the fix)",
              !ProgressionEngine.carryPastOpenedWall(walledSave, gates: locked)
              && walledSave.seriesIndex == 1 && walledSave.matchIndex == SeriesProgress.matchesPerSeries)
        walledSave.replaySeriesIndex = -1
        walledSave.replayMatchIndex = -1
        check("with the game bought the walled save still has no match until it is carried on",
              ProgressionEngine.nextMatch(state: walledSave, gates: open) == nil
              && !ProgressionEngine.replaysAvailable(state: walledSave, gates: open))
        walledSave.replaySeriesIndex = 1
        walledSave.replayMatchIndex = 2
        let moved = ProgressionEngine.carryPastOpenedWall(walledSave, gates: open)
        check("buying the game carries the walled save into Series 3 cleanly",
              moved && walledSave.seriesIndex == 2 && walledSave.matchIndex == 0
              && walledSave.attempts == 0 && !walledSave.isReplaying
              && walledSave.tier == .national && walledSave.tierRaw == CareerTier.national.rawValue
              && walledSave.levelPoints == walled.pointsAfter,
              detail: "S\(walledSave.seriesIndex) M\(walledSave.matchIndex) A\(walledSave.attempts)")
        let firstPaid = ProgressionEngine.nextMatch(state: walledSave, gates: open)
        check("and Series 3, match 1 is on the card",
              firstPaid?.seriesIndex == 2 && firstPaid?.matchIndex == 0 && firstPaid?.isReplay == false)
        check("carrying on happens once: a second launch leaves the save where it is",
              !ProgressionEngine.carryPastOpenedWall(walledSave, gates: open)
              && walledSave.seriesIndex == 2 && walledSave.matchIndex == 0)
        // Relaunch after a purchase or a restore: the save on disk is still the walled one, and the
        // first fetch of the career (`CareerStore.state`) runs the same carry with the new gates.
        let relaunched = sampleState(seriesIndex: 1, matchIndex: SeriesProgress.matchesPerSeries, points: 3_200)
        check("a walled save relaunched after a restore carries on at Series 3",
              ProgressionEngine.carryPastOpenedWall(relaunched, gates: open)
              && relaunched.seriesIndex == 2 && relaunched.matchIndex == 0
              && ProgressionEngine.nextMatch(state: relaunched, gates: open) != nil)
        check("a save part way through a Series is never moved by the purchase",
              ProgressionEngine.openedWallAdvance(seriesIndex: 1, matchIndex: 3,
                                                  campaignComplete: false, gates: open) == nil)
        check("a finished campaign is never moved by the purchase",
              ProgressionEngine.openedWallAdvance(seriesIndex: 4, matchIndex: SeriesProgress.matchesPerSeries,
                                                  campaignComplete: true, gates: open) == nil
              && ProgressionEngine.openedWallAdvance(seriesIndex: 4, matchIndex: SeriesProgress.matchesPerSeries,
                                                     campaignComplete: false, gates: open) == nil)

        let regionalOpen = CareerEngine.tierWon(at: .regional, gates: open)
        check("an unlocked Series 2 final advances to Series 3",
              regionalOpen.advancedTo == .national && !regionalOpen.hitTheWall)
        check("every Series advances to the next one when the game is bought",
              CareerTier.allCases.dropLast().allSatisfy { tier in
                  CareerEngine.tierWon(at: tier, gates: open).advancedTo == tier.next
              })
        check("no Series hits the wall when the game is bought",
              CareerTier.allCases.allSatisfy { !CareerEngine.tierWon(at: $0, gates: open).hitTheWall })
        let masters = CareerEngine.tierWon(at: .masters, gates: open)
        check("Series 5's final is the end of the ladder",
              masters.wonTheLot && masters.advancedTo == nil && !masters.hitTheWall)
        check("the six arenas are all open when the game is bought",
              Catalogue.shared.arenas.allSatisfy { open.arenaAvailable($0.id) })

        // The engine REFUSES, it does not merely hide the button (coverage row section 14). A save
        // standing in Series 3 with no entitlement is the case an advance can never produce: an
        // entitlement that lapsed, a Family Sharing organiser who turned it off, a `-career`
        // fixture, or a build run with `-locked`. The save is not touched; the MATCH is refused.
        check("the free game's last Series is Series 2",
              ProgressionEngine.lastOpenSeries(gates: locked) == 1
              && ProgressionEngine.lastOpenSeries(gates: open) == 4)
        for seriesIndex in 0..<SeriesProgress.seriesCount {
            let standing = sampleState(seriesIndex: seriesIndex, matchIndex: 0, points: 3_300)
            let behind = ProgressionEngine.isBehindWall(state: standing, gates: locked)
            check("Series \(seriesIndex + 1) is \(seriesIndex > 1 ? "behind" : "in front of") the free game's wall",
                  behind == (seriesIndex > 1))
            check("Series \(seriesIndex + 1) hands out a match while locked only in front of the wall",
                  (ProgressionEngine.nextMatch(state: standing, gates: locked) != nil) == (seriesIndex <= 1))
            check("Series \(seriesIndex + 1) always hands out a match once the game is bought",
                  ProgressionEngine.nextMatch(state: standing, gates: open) != nil)
            check("no Series is behind the wall once the game is bought",
                  !ProgressionEngine.isBehindWall(state: standing, gates: open))
        }

        // And a match somehow fought behind the wall settles nothing at all.
        let smuggled = ProgressionEngine.settle(
            seriesIndex: 2, matchIndex: 0, attempts: 0, points: 3_300,
            result: .win, breakdown: ScrapBreakdown(base: 200, damage: 100, survivor: 100),
            isReplay: false, campaignComplete: false, gates: locked)
        check("a win behind the wall banks no scrap, no points and no advance",
              smuggled.hitTheWall && smuggled.scrap.total == 0 && smuggled.levelPoints == 0
              && smuggled.seriesIndex == 2 && smuggled.matchIndex == 0
              && smuggled.pointsAfter == 3_300)
        let allowed = ProgressionEngine.settle(
            seriesIndex: 2, matchIndex: 0, attempts: 0, points: 3_300,
            result: .win, breakdown: ScrapBreakdown(base: 200, damage: 100, survivor: 100),
            isReplay: false, campaignComplete: false, gates: open)
        check("and the same win with the game bought settles normally",
              !allowed.hitTheWall && allowed.scrap.total == 400 && allowed.matchIndex == 1)

        switch StoreService.override {
        case .locked:
            let gates = Gates(isUnlocked: false)
            check("-locked holds the player in Series 2",
                  gates.highestTier == .regional && gates.firstLockedTier == .national)
        case .unlocked:
            let gates = Gates(isUnlocked: true)
            check("-unlocked opens every Series",
                  gates.highestTier == .masters && gates.firstLockedTier == nil)
        case .none:
            say("no store override on this run: pass -locked or -unlocked to check one")
        }
    }

    // MARK: - Wave G: the house bot and the opponent's head

    private static func checkHouseBots() {
        let bosses = Set(CareerCatalogue.shared.bosses.map(\.id))
        check("there are bosses to put on duty", !bosses.isEmpty)

        for tier in CareerTier.allCases {
            for match in 0..<SeriesProgress.matchesPerSeries {
                let arena = CareerCatalogue.shared.progression.series(tier.index)?.arena(matchIndex: match)
                    ?? CareerEngine.arena(tier, round: match)
                let bot = CareerEngine.houseBot(tier: tier, arena: arena)
                check("Series \(tier.index + 1) match \(match + 1) has a house bot from the catalogue",
                      bosses.contains(bot.id), detail: bot.id)
                check("Series \(tier.index + 1) match \(match + 1) house bot speed is a real speed",
                      bot.speed > 0 && bot.speed <= 1, detail: "\(bot.speed)")
                check("Series \(tier.index + 1) match \(match + 1) house bot has a printable name",
                      CareerEngine.houseBotName(bot.id) == CareerCatalogue.shared.boss(bot.id)?.name)
            }
        }

        let scrapyard = CareerEngine.houseBot(tier: .scrapyard, arena: "yard")
        check("the Series 1 house bot is THRESHER at half speed",
              CareerEngine.houseBotName(scrapyard.id) == "THRESHER" && abs(scrapyard.speed - 0.5) < 0.0001,
              detail: "\(scrapyard.id) at \(scrapyard.speed)")

        let line = CareerEngine.houseBotLine(tier: .scrapyard, arena: "yard")
        check("the Series 1 scouting line names the bot, the zone and the release",
              line.contains("THRESHER") && line.contains("corner zone") && line.contains("two minutes"),
              detail: line)
        check("the Series 1 scouting line says it is the slow one", line.contains("half speed"))
        check("a full speed house bot does not claim to be slow",
              !CareerEngine.houseBotLine(tier: .masters, arena: "coliseum").contains("half speed"))
        check("no em dash reaches a house bot line",
              CareerTier.allCases.allSatisfy { tier in
                  let text = CareerEngine.houseBotLine(tier: tier, arena: CareerEngine.arena(tier, round: 0))
                  return !text.contains("\u{2014}") && !text.contains("\u{2013}")
              })
    }

    private static func checkOpponentHeads() {
        let five = ["brawler", "technician", "bully", "opportunist", "showboat"]
        check("the five temperaments are the contract's five",
              CareerEngine.temperaments.sorted() == five.sorted(),
              detail: CareerEngine.temperaments.joined(separator: ", "))
        check("the skill ids are the Series ids",
              CareerTier.allCases.allSatisfy { CareerEngine.aiSkill(for: $0) == $0.rawValue })

        var rivalsStable = true
        for rival in CareerCatalogue.shared.rivals {
            let entrant = CareerEntrant(
                id: rival.id, name: rival.name, roboteer: rival.roboteer, liveryHex: rival.liveryHex,
                kind: .rival, spec: rival.spec, rivalID: rival.id)
            let first = CareerEngine.temperament(for: entrant, seasonSeed: 1)
            let second = CareerEngine.temperament(for: entrant, seasonSeed: 987_654)
            if first != second || !CareerEngine.temperaments.contains(first) { rivalsStable = false }
            check("rival \(rival.name) has a temperament from the five",
                  CareerEngine.temperaments.contains(first), detail: first)
        }
        check("a rival's temperament does not move with the career seed", rivalsStable)

        var drawn = Set<String>()
        var illegal = 0
        for seed in 1...60 {
            var rng = SeededRandom(seed: seed)
            let filler = CareerEngine.fillerEntrant(index: seed % 8, tier: .regional, rng: &rng)
            let temperament = CareerEngine.temperament(for: filler, seasonSeed: seed)
            if !CareerEngine.temperaments.contains(temperament) { illegal += 1 }
            drawn.insert(temperament)
        }
        check("every filler temperament is one of the five", illegal == 0, detail: "\(illegal) were not")
        check("the filler field is not all one temperament", drawn.count > 1, detail: "\(drawn.count) drawn")
        check("the same filler and seed draw the same temperament",
              CareerEngine.temperament(fromID: "filler-3", salt: 77)
              == CareerEngine.temperament(fromID: "filler-3", salt: 77))
    }

    private static func checkHouseBotChoice() {
        let ids = Set(CareerCatalogue.shared.bosses.map(\.id))
        for tier in CareerTier.allCases {
            for arena in ["yard", "grinder", "drop_zone", "furnace", "crush", "coliseum"] {
                let house = CareerEngine.houseBot(tier: tier, arena: arena)
                check("Series \(tier.index + 1) in \(arena) is guarded by a boss that exists",
                      ids.contains(house.id), detail: house.id)
                check("Series \(tier.index + 1) in \(arena) house bot speed is sane",
                      house.speed > 0 && house.speed <= 1.0, detail: "\(house.speed)")
            }
        }
        check("Series 1 gets THRESHER at half speed",
              CareerEngine.houseBot(tier: .scrapyard, arena: "yard") == ("thresher", 0.5))
        check("Series 2 gets CINDER at full speed",
              CareerEngine.houseBot(tier: .regional, arena: "grinder") == ("cinder", 1.0))
        check("Series 3 fields BANDSAW or GRUDGE",
              ["bandsaw", "grudge"].contains(CareerEngine.houseBot(tier: .national, arena: "drop_zone").id))
        check("Series 4 fields ANVIL or THRESHER",
              ["anvil", "thresher"].contains(CareerEngine.houseBot(tier: .championship, arena: "furnace").id))
        check("the Crush pairs with THRESHER in Series 4",
              CareerEngine.houseBot(tier: .championship, arena: "crush").id == "thresher")
        check("Series 5 pairs the boss to the arena",
              CareerEngine.bossForArena("drop_zone") == "cinder"
              && CareerEngine.bossForArena("furnace") == "grudge"
              && CareerEngine.bossForArena("crush") == "thresher"
              && CareerEngine.bossForArena("coliseum") == "anvil")
        check("the same Series and arena always name the same house bot",
              CareerEngine.houseBot(tier: .masters, arena: "coliseum")
              == CareerEngine.houseBot(tier: .masters, arena: "coliseum"))

        #if !HARNESS
        // Quick Fight: the toggle is on from Series 2 up and off in Series 1, until the player
        // says otherwise, and what they say is remembered.
        check("a quick fight at Series 1 has no house bot by default",
              QuickFightChoice().houseBotOn(tier: .scrapyard) == false)
        check("a quick fight above Series 1 has one by default",
              CareerTier.allCases.filter { $0 != .scrapyard }
                  .allSatisfy { QuickFightChoice().houseBotOn(tier: $0) })
        var chosen = QuickFightChoice()
        chosen.houseBot = false
        check("a quick fight remembers the toggle being turned off",
              chosen.houseBotOn(tier: .masters) == false)
        #endif
    }

    // MARK: - Plain words

    /// Every string the engine can put on screen, against the two standing rules: no em dash, and
    /// never the words tier, circuit, season or bracket. "Circuitry" is a paint job and keeps its
    /// name, so the check is on whole words.
    private static func checkPlainWords() {
        var strings: [String] = []

        for index in 0..<SeriesProgress.seriesCount {
            strings.append(ProgressionEngine.seriesName(index))
            strings.append(ProgressionEngine.seriesLine(index))
            let tier = CareerTier.allCases[index]
            strings.append(tier.title)
            strings.append(CareerEngine.houseBotLine(tier: tier, arena: CareerEngine.arena(tier, round: 0)))
            strings.append(CareerEngine.tierWon(at: tier, gates: Gates(isUnlocked: false)).sentence)
            strings.append(Gates(isUnlocked: false).lockedReason(.tier(tier)))
        }
        for id in Catalogue.shared.allPartIDs {
            strings.append(ProgressionEngine.displayName(id))
            strings.append(ProgressionEngine.blurb(id))
        }
        for job in ProgressionEngine.paintJobs(level: 100) { strings.append(job.name) }
        for outcome in ["ko", "out_of_arena", "component_kill", "judges", "timeout", "forfeit"] {
            strings.append(ProgressionEngine.note(outcome: outcome, atSeconds: 34))
        }

        let state = sampleState()
        for series in 0..<SeriesProgress.seriesCount {
            for match in 0..<SeriesProgress.matchesPerSeries {
                state.seriesIndex = series
                state.matchIndex = match
                guard let card = ProgressionEngine.nextMatch(state: state, gates: .open) else { continue }
                strings.append(contentsOf: [card.title, card.arenaName, card.scoutingLine,
                                            card.houseBotLine, card.partsLine, card.opponent.name])
            }
            state.matchIndex = 0
            strings.append(contentsOf: ProgressionEngine.seriesSlots(state: state, seriesIndex: series)
                .map(\.opponentName))
        }

        let report = ProgressionEngine.matchReport(
            result: FightResult(json: resultV2), spec: .tinribs, startDamage: nil,
            botName: "Tinribs", opponentName: "Clatterbox", resultJSON: resultV2)
        strings.append(contentsOf: report.parts.map(\.label))
        strings.append(contentsOf: report.partsLost)
        strings.append(contentsOf: [SeriesProgress().line, report.durationText])
        for entry in ProgressionEngine.shopEntries(state: state, gates: .open) {
            strings.append(contentsOf: [entry.name, entry.blurb])
        }
        let log = FightLog()
        log.tier = .regional
        log.round = 2
        log.didWin = true
        log.outcome = "ko"
        strings.append(log.line)

        let dashed = strings.filter { $0.contains("\u{2014}") || $0.contains("\u{2013}") }
        check("no em dash or en dash reaches the player", dashed.isEmpty,
              detail: dashed.prefix(3).joined(separator: " | "))

        let banned = ["tier", "tiers", "circuit", "circuits", "season", "seasons", "bracket", "brackets"]
        var offenders: [String] = []
        for text in strings {
            let words = text.lowercased().split { !$0.isLetter }.map(String.init)
            if words.contains(where: { banned.contains($0) }) { offenders.append(text) }
        }
        check("the words tier, circuit, season and bracket never reach the player",
              offenders.isEmpty, detail: offenders.prefix(3).joined(separator: " | "))
        check("the strings really were collected", strings.count > 150, detail: "\(strings.count)")

        let idLike = strings.filter { $0.contains("_") }
        check("no string is left as an id", idLike.isEmpty,
              detail: idLike.prefix(3).joined(separator: " | "))
    }

    // MARK: - Front end fixes (docs/aaa/frontend-meta.md section 8, wave A)

    private static func checkFrontEndFixes() {
        // Bug 3: armour materials and every other part are owned before they are fought with.
        let starting = ProgressionEngine.startingOwned
        check("the starting machine is built only from parts a new career owns",
              ProgressionEngine.unownedParts(in: .tinribs, owned: starting).isEmpty
              && ProgressionEngine.unownedParts(in: .defaultWedge, owned: starting).isEmpty,
              detail: (ProgressionEngine.unownedParts(in: .tinribs, owned: starting)
                       + ProgressionEngine.unownedParts(in: .defaultWedge, owned: starting)).joined(separator: ", "))
        check("armour materials are counted as parts of the machine",
              ProgressionEngine.partIDs(in: .defaultWedge).contains("steel")
              && ProgressionEngine.partIDs(in: .defaultWedge).contains("hdpe"))
        var plated = BuildSpec.tinribs
        plated.armour["front"] = ArmourFaceSpec(material: "reinforced", thickness: 2)
        plated.armour["rear"] = ArmourFaceSpec(material: "reactive", thickness: 1)
        check("Reinforced and Reactive are not in a new career's hands",
              !starting.contains("reinforced") && !starting.contains("reactive"))
        check("a machine plated in Reinforced and Reactive is refused at FIGHT",
              ProgressionEngine.unownedParts(in: plated, owned: starting) == ["reinforced", "reactive"]
              && ProgressionEngine.ownershipFault(in: plated, owned: starting) != nil)
        check("the same machine fights once both are bought",
              ProgressionEngine.ownershipFault(in: plated, owned: starting + ["reinforced", "reactive"]) == nil)
        check("the free game's wall covers Reactive but not Reinforced",
              Gates(isUnlocked: false).partAvailable("reinforced") && !Gates(isUnlocked: false).partAvailable("reactive"))

        // Bug 4: RETRY is off, with the fix named, whenever the machine cannot go back in.
        check("a fit machine can retry", ProgressionEngine.retryBlock(
            fault: nil, legal: true, ownership: nil, repairBill: 184, scrap: 90) == nil)
        let affordable = ProgressionEngine.retryBlock(
            fault: "Core destroyed", legal: true, ownership: nil, repairBill: 184, scrap: 620) ?? ""
        check("a dead core with the bill affordable points at repair and retry",
              affordable.contains("Repair it for 184"), detail: affordable)
        let stranded = ProgressionEngine.retryBlock(
            fault: "Core destroyed", legal: true, ownership: nil, repairBill: 641, scrap: 40) ?? ""
        check("a dead core the player cannot pay for points at the garage",
              stranded.contains("641") && stranded.contains("40") && stranded.contains("garage"), detail: stranded)
        check("an illegal machine cannot retry",
              ProgressionEngine.retryBlock(fault: nil, legal: false, ownership: nil, repairBill: 0, scrap: 0) != nil)
        check("a machine with a part it does not own cannot retry",
              ProgressionEngine.retryBlock(fault: nil, legal: true,
                                           ownership: ProgressionEngine.ownershipFault(in: plated, owned: starting),
                                           repairBill: 0, scrap: 0) != nil)

        // Owner decision 1: the stranded player gets a free patch-up to 25 %, and nobody else does.
        check("a stranded machine is offered the free patch-up",
              ProgressionEngine.emergencyPatchAllowed(fault: "Core destroyed", repairBill: 641, scrap: 40, otherFitMachine: false))
        check("no patch-up when the bill can be paid",
              !ProgressionEngine.emergencyPatchAllowed(fault: "Core destroyed", repairBill: 641, scrap: 700, otherFitMachine: false))
        check("no patch-up when another machine can fight",
              !ProgressionEngine.emergencyPatchAllowed(fault: "Core destroyed", repairBill: 641, scrap: 40, otherFitMachine: true))
        check("no patch-up for a machine that can already fight",
              !ProgressionEngine.emergencyPatchAllowed(fault: nil, repairBill: 641, scrap: 40, otherFitMachine: false))
        let wrecked: [String: Any] = [
            "wheels": [0.0, 0.0, 0.0, 0.6], "weapon": 0.0, "drive": 0.1, "core": 0.0,
            "armour": ["front": 0.0, "sides": 0.5, "rear": 1.0, "top": 1.0]
        ]
        let patched = ProgressionEngine.emergencyPatched(wrecked)
        let patchedWheels = patched["wheels"] as? [Double] ?? []
        check("the patch-up brings core, weapon, drive and wheels to 25 %",
              patched["core"] as? Double == 0.25 && patched["weapon"] as? Double == 0.25
              && patched["drive"] as? Double == 0.25 && patchedWheels == [0.25, 0.25, 0.25, 0.6])
        check("the patch-up leaves the armour as it was",
              (patched["armour"] as? [String: Double])?["front"] == 0.0)
        let patchedBot = BotBuild(spec: .tinribs)
        patchedBot.damageJSON = JSONText.string(from: wrecked)
        check("a wrecked machine is unfit before the patch-up", patchedBot.fitnessFault != nil)
        patchedBot.damageJSON = JSONText.string(from: patched)
        check("and fit to fight after it", patchedBot.fitnessFault == nil,
              detail: patchedBot.fitnessFault ?? "")
        let patchLine = ProgressionEngine.retryBlock(fault: "Core destroyed", legal: true, ownership: nil,
                                                     repairBill: 641, scrap: 40, canPatch: true) ?? ""
        check("the stranded retry sentence names the free patch-up", patchLine.contains("25%"), detail: patchLine)

        // Bug 8: a draw is a draw on the quick fight sheet and on the career report alike.
        check("no winner reads as a draw", ProgressionEngine.resultKind(winner: "", playerID: "player-1") == .draw)
        check("the player's win reads as a win",
              ProgressionEngine.resultKind(winner: "player-1", playerID: "player-1") == .win)
        check("the other machine's win reads as a loss",
              ProgressionEngine.resultKind(winner: "ai-1", playerID: "player-1") == .loss)
        #if !HARNESS
        check("the quick fight's player id is the one the draw rule is asked about",
              ProgressionEngine.resultKind(winner: "", playerID: FightConfigFixture.playerID) == .draw)
        #endif

        // The new sentences follow the standing rules.
        let sentences = [affordable, stranded,
                         ProgressionEngine.ownershipFault(in: plated, owned: starting) ?? "",
                         ProgressionEngine.retryBlock(fault: nil, legal: false, ownership: nil, repairBill: 0, scrap: 0) ?? ""]
        check("the new retry and ownership sentences carry no em dash",
              !sentences.contains { $0.contains("\u{2014}") || $0.contains("\u{2013}") })

        #if !HARNESS
        checkPadFocusAfterFight()
        #endif
    }

    #if !HARNESS
    /// Bug 6, as far as it can be proved without a real pad: the Series screen's FIGHT is live,
    /// the fight clears the pad, and the match report, the rewards and the retry prompt each hold
    /// their own answer. The real pad check on a device is still owed (notes file).
    ///
    /// This drives the shared `PadFocus` with `handle`, which also turns the focus ring on for
    /// the rest of the run. It only runs under `-careerSelfTest`, so a player never sees it.
    private static func checkPadFocusAfterFight() {
        let focus = PadFocus.shared
        var fired: [String] = []

        focus.set([PadItem("fight") { fired.append("fight") }], back: { fired.append("home.back") })
        // What `CareerFightView.start` and `CareerRootView.go` now do.
        focus.clear()
        focus.handle(.activate)
        focus.handle(.back)
        check("after the fight clears the pad, A and B fire nothing from the Series screen",
              fired.isEmpty, detail: fired.joined(separator: ", "))

        focus.set(MatchReportView.padItems { fired.append("report.continue") }, back: nil)
        focus.handle(.activate)
        check("A on the match report continues the report, never FIGHT",
              fired == ["report.continue"], detail: fired.joined(separator: ", "))

        fired = []
        focus.clear()
        focus.set(RewardsView.padItems { fired.append("rewards.continue") }, back: nil)
        focus.handle(.back)
        focus.handle(.activate)
        check("B on the rewards does nothing and A continues",
              fired == ["rewards.continue"], detail: fired.joined(separator: ", "))

        fired = []
        focus.clear()
        focus.set(RetryPromptView.padItems(
            canRetry: false, showsRepair: true, canRepairAndRetry: true,
            onRetry: { fired.append("retry") },
            onRepairAndRetry: { fired.append("repair") },
            onGarage: { fired.append("garage") }), back: { fired.append("garage") })
        focus.handle(.activate)
        check("with RETRY off, the pad lands on the repair and never fires RETRY",
              fired == ["repair"], detail: fired.joined(separator: ", "))

        fired = []
        focus.clear()
        focus.set(RetryPromptView.padItems(
            canRetry: false, showsRepair: true, canRepairAndRetry: false,
            onRetry: { fired.append("retry") },
            onRepairAndRetry: { fired.append("repair") },
            onGarage: { fired.append("garage") }), back: { fired.append("garage") })
        focus.handle(.activate)
        check("a stranded machine's only pad answer is the garage", fired == ["garage"],
              detail: fired.joined(separator: ", "))
        focus.clear()
    }
    #endif

    // MARK: - Wave B: medals (owner decision 3)

    private static func report(_ result: MatchReport.Result, outcome: String = "judges", kept: Double = 1,
                               lost: [String] = [], scrap: ScrapBreakdown? = nil) -> MatchReport {
        MatchReport(result: result, outcome: outcome, durationSeconds: 150, hitsLanded: 10, hitsTaken: 4,
                    parts: [PartCondition(label: "Core", condition: kept, startCondition: 1),
                            PartCondition(label: "Weapon", condition: kept, startCondition: 1)],
                    partsLost: lost, botName: "Tinribs", opponentName: "Clatterbox", scrap: scrap)
    }

    private static func checkMedals() {
        let rules = ProgressionEngine.scrapRules(seriesIndex: 1)
        check("three medals a match, sixty in the campaign", MedalBoard.perMatch == 3 && MedalBoard.total == 60)
        check("a loss earns no medal", ProgressionEngine.medals(for: report(.loss, outcome: "ko")).isEmpty)
        check("a draw earns no medal", ProgressionEngine.medals(for: report(.draw)).isEmpty)
        let points = ProgressionEngine.medals(for: report(.win, kept: 0.5, lost: ["Front armour"]), rules: rules)
        check("a battered judges win is the win medal only", points == [.win], detail: "\(points)")
        let survivor = ProgressionEngine.medals(
            for: report(.win, kept: 0.5, lost: ["Front armour"], scrap: ScrapBreakdown(base: 1, survivor: 5)), rules: rules)
        check("the arena's survivor line earns Survivor when the rules pay one", survivor == [.win, .survivor])
        let noSurvivorLine = ProgressionEngine.medals(
            for: report(.win, kept: 0.9, lost: ["Front armour"], scrap: ScrapBreakdown(base: 1, survivor: 0)), rules: rules)
        check("the arena's word is taken over the condition when the rules pay a survivor line",
              noSurvivorLine == [.win], detail: "\(noSurvivorLine)")
        let byCondition = ProgressionEngine.medals(for: report(.win, kept: 0.75, lost: ["Front armour"]), rules: ScrapRules())
        check("with no survivor line, over 70 % kept earns Survivor", byCondition == [.win, .survivor])
        check("with no survivor line, under 70 % kept does not",
              ProgressionEngine.medals(for: report(.win, kept: 0.65, lost: ["Front armour"]), rules: ScrapRules()) == [.win])
        check("a knockout earns the finisher",
              ProgressionEngine.medals(for: report(.win, outcome: "ko", kept: 0.2, lost: ["Weapon"]), rules: rules)
              == [.win, .finisher])
        check("out of the arena and a core kill are knockouts too",
              ["out_of_arena", "component_kill"].allSatisfy {
                  ProgressionEngine.medals(for: report(.win, outcome: $0, kept: 0.2, lost: ["Weapon"]), rules: rules)
                      .contains(.finisher)
              })
        check("a flawless judges win earns the finisher (the arena's flawless line)",
              ProgressionEngine.medals(for: report(.win, kept: 1, scrap: ScrapBreakdown(base: 1, survivor: 5, flawless: 5)),
                                       rules: rules) == [.win, .survivor, .finisher])
        check("with no flawless line, no part lost is flawless",
              ProgressionEngine.medals(for: report(.win, kept: 0.5), rules: ScrapRules()).contains(.finisher))
        check("every medal kind has a name and a line",
              MedalKind.allCases.allSatisfy { !$0.name.isEmpty && !$0.line.isEmpty })

        // Settling: a first win keeps every medal it earned as new; the keys are per match.
        let first = ProgressionEngine.settle(
            seriesIndex: 1, matchIndex: 2, attempts: 0, points: 1_400, result: .win,
            breakdown: ScrapBreakdown(base: 100, damage: 50, survivor: 50), isReplay: false,
            campaignComplete: false, medals: [.win, .survivor], medalsHeld: [], gates: .open)
        check("a first win's medals are all new", first.newMedals == [.win, .survivor])
        check("the medal keys name the match", first.newMedalKeys == ["s1.m2.win", "s1.m2.survivor"],
              detail: "\(first.newMedalKeys)")
        check("a first win pays no medal top up", first.medalTopUp == 0 && first.banked == 200)
        check("the rewards carry the medals", first.rewards?.medals == [.win, .survivor]
              && first.rewards?.bankedTotal == 200)
        check("a loss settles no medals",
              ProgressionEngine.settle(seriesIndex: 1, matchIndex: 2, attempts: 0, points: 0, result: .loss,
                                       breakdown: nil, isReplay: false, campaignComplete: false,
                                       medals: [.win], medalsHeld: [], gates: .open).newMedalKeys.isEmpty)

        // A replay with nothing new pays half; a replay that earns a new medal pays the match in full.
        let held = ["s0.m1.win", "s0.m1.survivor"]
        let half = ScrapBreakdown(base: 45, damage: 20, survivor: 23)
        let plain = ProgressionEngine.settle(
            seriesIndex: 0, matchIndex: 1, attempts: 0, points: 3_000, result: .win, breakdown: half,
            isReplay: true, campaignComplete: true, medals: [.win, .survivor], medalsHeld: held, gates: .open)
        check("a replay with no new medal pays the replay rate", plain.medalTopUp == 0 && plain.banked == half.total
              && plain.levelPoints == ProgressionEngine.winPoints(seriesIndex: 0, flawless: false, replay: true))
        let topped = ProgressionEngine.settle(
            seriesIndex: 0, matchIndex: 1, attempts: 0, points: 3_000, result: .win, breakdown: half,
            isReplay: true, campaignComplete: true, medals: [.win, .survivor, .finisher], medalsHeld: held, gates: .open)
        check("a replay that earns a new medal names only the new one", topped.newMedals == [.finisher])
        check("a replay that earns a new medal is topped up to the full match",
              topped.banked == Int((Double(half.total) / CareerCatalogue.shared.progression.replayScale).rounded()),
              detail: "\(topped.scrap.total) + \(topped.medalTopUp)")
        check("a replay that earns a new medal pays full points",
              topped.levelPoints == ProgressionEngine.winPoints(seriesIndex: 0, flawless: false, replay: false))
        check("the rewards show the top up", topped.rewards?.medalTopUp == topped.medalTopUp && topped.medalTopUp > 0)

        // The board.
        let state = sampleState(seriesIndex: 1, matchIndex: 0)
        state.medals = ["s0.m0.win", "s0.m0.survivor", "s0.m1.win"]
        let slots = ProgressionEngine.seriesSlots(state: state, seriesIndex: 0)
        check("the strip carries each match's medals",
              slots.first?.medals == [.win, .survivor] && slots.dropFirst().first?.medals == [.win]
              && (slots.last?.medals.isEmpty ?? false))
        check("the board counts out of sixty", state.medalBoard.line == "3 of 60 medals")
        check("a Series with a medal missing is not complete", !state.medalBoard.isComplete(seriesIndex: 0))
        check("a new career holds no medals", CareerState().medals.isEmpty)
    }

    // MARK: - Wave B: the opener (owner decision 9)

    private static func checkOpener() {
        let fresh = sampleState()
        let opener = ProgressionEngine.nextMatch(state: fresh, gates: .open)
        check("the first career match is a two minute opener",
              opener?.durationS == 120 && opener?.endgameAtS == 80,
              detail: "\(opener?.durationS ?? 0) / \(opener?.endgameAtS ?? 0)")
        check("the opener's house bot line says 1:20", opener?.houseBotLine.contains("1:20") ?? false,
              detail: opener?.houseBotLine ?? "")
        let second = ProgressionEngine.nextMatch(state: sampleState(seriesIndex: 0, matchIndex: 1), gates: .open)
        check("every other match is the full three minutes with the house bot at two",
              second?.durationS == 180 && second?.endgameAtS == 120
              && (second?.houseBotLine.contains("two minutes") ?? false))
        let retry = sampleState()
        retry.attempts = 2
        check("a retry of the first match is still the opener",
              ProgressionEngine.nextMatch(state: retry, gates: .open)?.durationS == 120)
        let replay = sampleState(seriesIndex: 4, matchIndex: 4)
        replay.campaignComplete = true
        replay.replaySeriesIndex = 0
        replay.replayMatchIndex = 0
        check("a replay of the first match is a full round",
              ProgressionEngine.nextMatch(state: replay, gates: .open)?.durationS == 180)

        #if !HARNESS
        let json = CareerFightConfig.json(player: [:], opponent: [:], arena: "yard", seed: 1,
                                          safeArea: SafeAreaPixels(left: 0, top: 0, right: 0, bottom: 0),
                                          next: opener)
        let rules = (JSONValue.parse(json)?["rules"])
        check("the fight config sends the opener's clock",
              rules?["duration_s"]?.intValue == 120 && rules?["endgame_at_s"]?.intValue == 80)
        check("the fight config sends the house bot when there is one",
              rules?["enforcer"]?.stringValue == opener?.houseBotID)
        let ladder = JSONValue.parse(CareerFightConfig.json(player: [:], opponent: [:], arena: "yard", seed: 1,
                                                            safeArea: SafeAreaPixels(left: 0, top: 0, right: 0, bottom: 0)))?["rules"]
        check("a fight with no card sends the full round and no house bot",
              ladder?["duration_s"]?.intValue == CareerFightConfig.fightDurationS && ladder?["enforcer"] == nil)
        #endif
    }

    // MARK: - Wave B: one garage (owner decision 12)

    private static func checkOneGarage() {
        let open = Gates.open
        let locked = Gates(isUnlocked: false)
        check("with no career the garage has the Scrapyard's slots",
              Garage.capacity(career: nil, gates: open) == 1)
        check("the garage grows with the Series",
              (0..<5).map { Garage.capacity(career: sampleState(seriesIndex: $0), gates: open) } == [1, 2, 3, 4, 5])
        check("the free game holds the garage at two",
              Garage.capacity(career: sampleState(seriesIndex: 4), gates: locked) == 2
              && Garage.capacity(career: sampleState(seriesIndex: 0), gates: locked) == 1)
        let one = BotBuild(spec: .tinribs)
        let two = BotBuild(spec: .defaultWedge)
        let dead = BotBuild(spec: .defaultWedge)
        dead.isWrittenOff = true
        check("the last machine cannot be scrapped", !Garage.canDelete([one]) && !Garage.canDelete([one, dead]))
        check("a machine can be scrapped while another is left", Garage.canDelete([one, two]))
    }

    // MARK: - Wave B: the taster (owner decision 13)

    private static func checkTaster() {
        let locked = Gates(isUnlocked: false)
        let open = Gates.open
        let taster = CareerCatalogue.shared.progression.taster
        check("the taster is one event and one ladder fight", taster.events == 1 && taster.ladderFights == 1)
        check("a free game may play its first side event", locked.sideEventOpen(tasterUsed: 0))
        check("a free game may not play a second", !locked.sideEventOpen(tasterUsed: 1))
        check("a free game may fight its first ladder fight", locked.ladderFightOpen(tasterUsed: 0))
        check("a free game may not fight a second", !locked.ladderFightOpen(tasterUsed: 1))
        check("the full game is never counted against the taster",
              open.sideEventOpen(tasterUsed: 9) && open.ladderFightOpen(tasterUsed: 9)
              && !open.spendsTaster(.sideEvents) && !open.spendsTaster(.ladder))
        check("a free game's play is spent from the taster",
              locked.spendsTaster(.sideEvents) && locked.spendsTaster(.ladder))
        check("the taster lines are plain words",
              !locked.tasterLine(.ladder, left: 1).contains("\u{2014}") && !locked.tasterLine(.sideEvents, left: 1).isEmpty)
        check("an event may not hand over a part behind the wall",
              !locked.partAvailable("apex") && locked.partAvailable("flipper"))
        check("a new career has used no taster", CareerState().tasterEventsUsed == 0 && CareerState().tasterLadderUsed == 0)
    }

    // MARK: - Wave B: the ladder is an exhibition (brief v5 section 9.3)

    private static func checkLadderExhibition() {
        let bot = BotBuild(spec: .tinribs)
        bot.damageJSON = JSONText.string(from: [
            "wheels": [1.0, 0.5, 1.0, 1.0], "weapon": 0.4, "drive": 0.9, "core": 0.3,
            "armour": ["front": 0.3, "sides": 1.0, "rear": 1.0, "top": 1.0]
        ])
        let sent = bot.toBotConfig(id: "player-1", controller: "player", pristine: true)
        let damage = sent["damage"] as? [String: Any]
        check("a ladder machine is sent pristine",
              (damage?["core"] as? Double) == 1.0 && (damage?["weapon"] as? Double) == 1.0)
        check("sending it pristine leaves its own damage alone", (bot.damageDictionary["core"] as? Double) == 0.3)
    }

    // MARK: - Wave B: the title defence (owner decision 8)

    private static func checkDefence() {
        let done = sampleState(seriesIndex: 4, matchIndex: SeriesProgress.matchesPerSeries)
        done.campaignComplete = true
        guard let first = ProgressionEngine.nextMatch(state: done, gates: .open) else {
            check("a won campaign offers the title defence", false)
            return
        }
        check("a won campaign offers the title defence", first.isDefence && first.title == "Title defence 1",
              detail: first.title)
        check("challenger 1 is the first on the list, at Masters strength",
              first.opponent.rivalID == "penny_dread" && first.tier == .masters && first.aiSkill == "masters")
        check("a defence pays half the Masters scrap and no points",
              first.scrapRules.base == Int((Double(ProgressionEngine.scrapRules(seriesIndex: 4).base) * 0.5).rounded())
              && first.winPoints == 0)
        check("a defence is a full round with a house bot", first.durationS == 180 && first.hasHouseBot)
        check("a defence's opponent is legal", BuildRules.isValid(first.opponent.spec))

        done.defenceStreak = 8
        let ninth = ProgressionEngine.nextMatch(state: done, gates: .open)
        check("challenger 9 is challenger 1 again", ninth?.opponent.rivalID == "penny_dread" && ninth?.title == "Title defence 9")
        check("every full cycle the house bot is a step faster",
              abs((ninth?.houseBotSpeed ?? 0) - (first.houseBotSpeed + 0.05)) < 0.0001,
              detail: "\(ninth?.houseBotSpeed ?? 0)")
        done.defenceStreak = 400
        check("the house bot's speed has a cap",
              (ProgressionEngine.nextMatch(state: done, gates: .open)?.houseBotSpeed ?? 9) <= 1.25)
        check("the arena cycles through the six",
              (1...6).map { PostCampaign.defenceArena($0) } == CareerCatalogue.shared.progression.defence.arenas)
        done.defenceStreak = 0

        let replaying = sampleState(seriesIndex: 4, matchIndex: 4)
        replaying.campaignComplete = true
        replaying.replaySeriesIndex = 2
        replaying.replayMatchIndex = 1
        check("a queued replay comes before the defence",
              ProgressionEngine.nextMatch(state: replaying, gates: .open)?.isReplay ?? false)
        check("the defence needs the whole game",
              ProgressionEngine.nextMatch(state: done, gates: Gates(isUnlocked: false)) == nil)
        check("a campaign still running has no defence",
              !(ProgressionEngine.nextMatch(state: sampleState(seriesIndex: 4, matchIndex: 3), gates: .open)?.isDefence ?? true))

        let won = PostCampaign.settleDefence(number: 1, streak: 0, best: 0, points: 9_900, result: .win,
                                             breakdown: ScrapBreakdown(base: 130, damage: 60, survivor: 65))
        check("a defended title extends the reign and banks the scrap",
              won.streakAfter == 1 && won.bestAfter == 1 && won.banked == 255 && won.rewards?.levelPoints == 0)
        check("the defence rewards say so in the headline", !(won.rewards?.headline.isEmpty ?? true),
              detail: won.rewards?.headline ?? "")
        let lost = PostCampaign.settleDefence(number: 4, streak: 3, best: 5, points: 9_900, result: .loss,
                                              breakdown: ScrapBreakdown(base: 130))
        check("a loss ends the reign and keeps the best",
              lost.streakAfter == 0 && lost.bestAfter == 5 && lost.banked == 0 && lost.rewards == nil)
        let drawn = PostCampaign.settleDefence(number: 4, streak: 3, best: 5, points: 9_900, result: .draw,
                                               breakdown: nil)
        check("a draw leaves the reign standing", drawn.streakAfter == 3 && drawn.banked == 0)
        let best = PostCampaign.settleDefence(number: 6, streak: 5, best: 5, points: 9_900, result: .win, breakdown: nil)
        check("a reign past the best is the new best", best.streakAfter == 6 && best.bestAfter == 6)
        check("the reign lines are plain words",
              [PostCampaign.reignLine(streak: 1, best: 1), PostCampaign.reignLine(streak: 3, best: 3),
               PostCampaign.reignLine(streak: 2, best: 6)].allSatisfy { !$0.contains("\u{2014}") && !$0.isEmpty })
    }

    // MARK: - Wave B: the daily exhibition (owner decision 8)

    private static func checkDaily() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let noon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 23, minute: 30)) ?? Date()
        check("the day key is the UTC date", PostCampaign.dayKey(noon) == "2026-09-25", detail: PostCampaign.dayKey(noon))
        let days = PostCampaign.playableDays(now: noon)
        check("the last seven days are playable", days.count == 7 && days.first == "2026-09-25" && days.last == "2026-09-19",
              detail: days.joined(separator: " "))
        check("the seed is the same every time for a day", PostCampaign.daySeed("2026-09-25") == PostCampaign.daySeed("2026-09-25"))
        check("the seed differs day to day", PostCampaign.daySeed("2026-09-25") != PostCampaign.daySeed("2026-09-26"))
        let card = PostCampaign.dailyCard("2026-09-25")
        check("a day's card is the same card every time", card == PostCampaign.dailyCard("2026-09-25"))
        check("a day's arena is on the list", CareerCatalogue.shared.progression.daily.arenas.contains(card.arena))
        check("a day's opponent is legal", BuildRules.isValid(card.opponent.spec))

        // Over a year of days every twist comes up, and each twist does what it says.
        var twists = Set<String>()
        var sane = true
        for offset in 0..<365 {
            let key = PostCampaign.dayKey(noon.addingTimeInterval(Double(offset) * 86_400))
            let day = PostCampaign.dailyCard(key)
            twists.insert(day.twist.id)
            switch day.twist.id {
            case "sprint": sane = sane && day.durationS == 90 && day.endgameAtS == 60
            case "open_corner": sane = sane && day.houseBotID.isEmpty
            case "heavyweight": sane = sane && day.tier == .masters
            case "house_hunts": sane = sane && day.houseBotSpeed > 1.0
            default: sane = sane && day.durationS == 180 && !day.houseBotID.isEmpty
            }
        }
        check("every twist comes up in a year",
              twists == Set(CareerCatalogue.shared.progression.daily.twists.map(\.id)), detail: twists.sorted().joined(separator: ", "))
        check("every twist does what it says", sane)

        let match = PostCampaign.dailyMatch(card)
        check("the daily banks nothing", match.scrapRules == ScrapRules() && match.winPoints == 0 && match.isDaily)
        check("the daily's title is plain", match.title == "Daily exhibition")
        #if !HARNESS
        let openDay = (0..<365).lazy.map { PostCampaign.dailyCard(PostCampaign.dayKey(noon.addingTimeInterval(Double($0) * 86_400))) }
            .first { $0.twist.id == "open_corner" }
        if let openDay {
            let rules = JSONValue.parse(CareerFightConfig.json(
                player: [:], opponent: [:], arena: openDay.arena, seed: openDay.seed,
                safeArea: SafeAreaPixels(left: 0, top: 0, right: 0, bottom: 0),
                next: PostCampaign.dailyMatch(openDay)))?["rules"]
            check("an open corner sends no house bot", rules?["enforcer"] == nil && rules?["duration_s"]?.intValue == 180)
        }
        #endif

        let score = PostCampaign.dailyScore(won: true, opponentRemoved: 0.5, ownLeft: 0.8, secondsLeft: 60, hitsLanded: 12)
        check("the score is the published formula",
              score.win == 1_000 && score.damage == 300 && score.health == 320 && score.time == 180 && score.hits == 120
              && score.total == 1_920, detail: "\(score.total)")
        let losing = PostCampaign.dailyScore(won: false, opponentRemoved: 0.3, ownLeft: 0, secondsLeft: 60, hitsLanded: 4)
        check("a loss scores no win and no time", losing.win == 0 && losing.time == 0 && losing.total == 180 + 40)
        let fromResult = PostCampaign.dailyScore(card: card, playerSpec: .tinribs, result: FightResult(json: resultV2),
                                                 resultJSON: resultV2)
        check("a fought result scores the win, the time left and the hits",
              fromResult.win == 1_000 && fromResult.hits == 120 && fromResult.time > 0, detail: "\(fromResult)")
        check("no result scores nothing",
              PostCampaign.dailyScore(card: card, playerSpec: .tinribs, result: nil, resultJSON: "").total == 0)

        let one = PostCampaign.recordingDaily(900, key: "2026-09-25", in: "", now: noon)
        let lower = PostCampaign.recordingDaily(500, key: "2026-09-25", in: one.json, now: noon)
        let higher = PostCampaign.recordingDaily(1_200, key: "2026-09-25", in: lower.json, now: noon)
        check("the best per day is kept",
              one.isBest && !lower.isBest && higher.isBest && PostCampaign.dailyBests(higher.json)["2026-09-25"] == 1_200)
        let stale = PostCampaign.recordingDaily(10, key: "2026-09-25", in: "{\"2026-08-01\": 5000}", now: noon)
        check("days that can no longer be played are dropped", PostCampaign.dailyBests(stale.json)["2026-08-01"] == nil)
        check("the leaderboard is daily_exhibition", CareerCatalogue.shared.progression.daily.leaderboard == "daily_exhibition")

        let complete = sampleState(seriesIndex: 4, matchIndex: 4)
        complete.campaignComplete = true
        check("the daily opens once the campaign is won", PostCampaign.dailyAvailable(state: complete, gates: .open))
        check("the daily is shut while the campaign runs", !PostCampaign.dailyAvailable(state: sampleState(), gates: .open))
    }

    // MARK: - Wave B: pacing (the whole campaign, bought and repaired as a player would)

    private struct Pacing {
        var wins = 0
        var complete = false
        var earned = [Int](repeating: 0, count: SeriesProgress.seriesCount)
        var repairs = [Int](repeating: 0, count: SeriesProgress.seriesCount)
        var bought = [Int](repeating: 0, count: SeriesProgress.seriesCount)
        var repairPerFight = [Int](repeating: 0, count: SeriesProgress.seriesCount)
        var left = 0
        var lowest = 0
        var clearedAt = 0
        var worstWait = (id: "none", wins: 0)
        var minutes = 0.0
    }

    /// A player who wins every match in `attempts` tries (rising by Series), is paid base plus half
    /// the damage bonus plus the survivor bonus on the win, pays a repair after every fight when
    /// `repairing` (a machine at that Series' strength coming home about a fifth down: front armour
    /// 55 %, weapon 75 %, core 80 %), and buys each part the moment its Level opens and the bank
    /// can pay, in ladder order.
    private static func pacingRun(repairing: Bool) -> Pacing {
        let attemptsPerWin = [1.3, 1.4, 1.5, 1.55, 1.6]
        let fightMinutes = 2.5, openerMinutes = 2.0, menuMinutes = 1.5
        let ladder = ProgressionEngine.progression.levelRequired
            .filter { Catalogue.shared.allPartIDs.contains($0.key) }
            .sorted { ($0.value, $0.key) < ($1.value, $1.key) }
        var owned = Set(ProgressionEngine.startingOwned)
        var out = Pacing()
        var scrap = ProgressionEngine.openingScrap
        out.lowest = scrap
        var points = 0, series = 0, match = 0
        var waited: [String: Int] = [:]

        while !out.complete, out.wins < 40 {
            let tier = CareerTier.allCases[series]
            let rules = ProgressionEngine.scrapRules(seriesIndex: series)
            let attempts = attemptsPerWin[series]
            let machine = CareerEngine.rivalSpec(CareerCatalogue.shared.rivals[0], at: tier)
            var damage = FightResult.BotDamage()
            damage.wheels = [1, 0.8, 1, 0.9]
            damage.weapon = 0.75
            damage.drive = 0.9
            damage.core = 0.8
            damage.armour = FightResult.Armour(front: 0.55, sides: 0.8, rear: 0.9, top: 1)
            let perFight = CareerEngine.repairBill(for: machine, damage: damage).total
            out.repairPerFight[series] = perFight
            let repairs = repairing ? Int((Double(perFight) * attempts).rounded()) : 0

            let settled = ProgressionEngine.settle(
                seriesIndex: series, matchIndex: match, attempts: 0, points: points, owned: Array(owned),
                result: .win,
                breakdown: ScrapBreakdown(base: rules.base, damage: rules.damageFull / 2, survivor: rules.survivor),
                isReplay: false, campaignComplete: false, medals: [.win, .survivor], medalsHeld: [], gates: .open)
            out.wins += 1
            scrap += settled.banked - repairs
            out.lowest = min(out.lowest, scrap)
            out.earned[series] += settled.banked
            out.repairs[series] += repairs
            points = settled.pointsAfter
            out.minutes += attempts * ((out.wins == 1 ? openerMinutes : fightMinutes) + menuMinutes)

            let level = ProgressionEngine.level(points: points).level
            for (id, required) in ladder where required <= level && !owned.contains(id) {
                waited[id, default: 0] += 1
                let price = ProgressionEngine.price(id)
                guard scrap >= price else { continue }
                scrap -= price
                owned.insert(id)
                out.bought[series] += price
                if waited[id, default: 1] - 1 > out.worstWait.wins { out.worstWait = (id, waited[id, default: 1] - 1) }
            }
            if out.clearedAt == 0, ladder.allSatisfy({ owned.contains($0.key) }) { out.clearedAt = out.wins }
            out.complete = settled.campaignComplete
            series = settled.seriesIndex
            match = settled.matchIndex
        }
        out.left = scrap
        return out
    }

    /// The pacing numbers the owner asked for: scrap per campaign, the shop total, hours. Printed,
    /// not judged: the only hard checks are that the campaign runs its twenty wins and that a
    /// player who does not repair clears the shop. The repair case is a WARNING when it goes
    /// broke, because it turns on how hard the arena hits, which the sim can only assume.
    private static func checkPacing() {
        let owned = Set(ProgressionEngine.startingOwned)
        let shopTotal = Catalogue.shared.allPartIDs.filter { !owned.contains($0) }
            .map { ProgressionEngine.price($0) }.reduce(0, +)
        let lean = pacingRun(repairing: false)
        let real = pacingRun(repairing: true)
        check("the pacing run finishes the campaign in twenty wins", real.complete && real.wins == 20,
              detail: "\(real.wins)")
        check("a player who never repairs clears the whole shop inside the campaign", lean.clearedAt > 0,
              detail: "\(lean.left) left")
        check("a player who never repairs buys every part within two wins of it opening", lean.worstWait.wins <= 2,
              detail: "\(lean.worstWait.id) waited \(lean.worstWait.wins)")
        if real.lowest < 0 {
            warn("pacing: a player who repairs every fight (\(real.repairPerFight) a fight by Series) dips to \(real.lowest) scrap")
        }
        if real.worstWait.wins > 2 {
            warn("pacing: repairing every fight, \(real.worstWait.id) waits \(real.worstWait.wins) wins to be bought")
        }
        let total = lean.earned.reduce(0, +)
        say("pacing: scrap per campaign \(total) (\(lean.earned) by Series) plus the \(ProgressionEngine.openingScrap) float; the shop costs \(shopTotal) to clear")
        say("pacing, no repairs: shop cleared on win \(lean.clearedAt), \(lean.left) left at the end, longest wait \(lean.worstWait.wins) wins (\(lean.worstWait.id))")
        say("pacing, repairing every fight: repair \(real.repairPerFight) a fight by Series, \(real.repairs) paid by Series, \(real.bought) spent in the shop by Series; shop cleared on win \(real.clearedAt == 0 ? "never" : "\(real.clearedAt)"), \(real.left) left, lowest bank \(real.lowest)")
        say("pacing: about \(String(format: "%.1f", real.minutes / 60)) hours for the campaign (1.3 to 1.6 tries a win, 2.5 min a fight, 2 for the opener, 1.5 of menus)")
    }

    // MARK: - Helpers

    private static func samplePlayer() -> CareerEntrant {
        CareerEntrant(
            id: "player",
            name: "Tinribs",
            roboteer: "You",
            liveryHex: LiveryPresets.defaultHex,
            kind: .player,
            spec: .tinribs
        )
    }

    /// A career in memory, never inserted into a store, for the pure checks.
    private static func sampleState(
        seriesIndex: Int = 0,
        matchIndex: Int = 0,
        points: Int = 0,
        scrap: Int = 300,
        seed: Int = 424_242
    ) -> CareerState {
        let state = CareerState(tier: CareerTier.allCases[min(max(0, seriesIndex), 4)],
                                scrap: scrap, seed: seed)
        state.seriesIndex = seriesIndex
        state.matchIndex = matchIndex
        state.levelPoints = points
        return state
    }

    private static func ladderLog() -> FightLog {
        let log = FightLog()
        log.tier = .regional
        log.round = 0
        log.didWin = true
        log.outcome = "ko"
        log.source = FightLog.Source.ladder
        return log
    }

    /// A FightResult v2 as agent C describes it: a won fight with every new block present.
    private static let resultV2 = """
    {"schema": 1, "duration_s": 74.0,
     "outcome": {"type": "ko", "winner": "player-1", "loser": "rival-1", "at_s": 74.0},
     "damage": {"player-1": {"wheels": [1.0, 0.4, 1.0, 0.0], "weapon": 0.5, "drive": 0.8,
                             "core": 0.9,
                             "armour": {"front": 0.3, "sides": 1.0, "rear": 1.0, "top": 1.0}}},
     "scrap": {"player-1": 270},
     "hits": {"player-1": {"landed": 12, "taken": 5}},
     "parts_lost": {"player-1": [{"part": "wheel_rr", "label": "Rear right wheel",
                                  "state": "destroyed"}]},
     "condition_start": {"player-1": {"wheels": [1.0, 1.0, 1.0, 1.0], "weapon": 1.0, "drive": 1.0,
                                      "core": 1.0,
                                      "armour": {"front": 1.0, "sides": 1.0, "rear": 1.0, "top": 1.0}}},
     "scrap_breakdown": {"player-1": {"base": 90, "damage": 90, "survivor": 45, "flawless": 45,
                                      "total": 270}}}
    """

    /// The same fight as a v1 result, which is what arrives until agent C's blocks land.
    private static let resultV1 = """
    {"schema": 1, "duration_s": 74.0,
     "outcome": {"type": "ko", "winner": "player-1", "loser": "rival-1", "at_s": 74.0},
     "damage": {"player-1": {"wheels": [1.0, 0.4, 1.0, 0.0], "weapon": 0.5, "drive": 0.8,
                             "core": 0.9,
                             "armour": {"front": 0.3, "sides": 1.0, "rear": 1.0, "top": 1.0}}},
     "scrap": {"player-1": 64}}
    """

    private static let lostResult = """
    {"schema": 1, "duration_s": 180.0,
     "outcome": {"type": "judges", "winner": "rival-1", "loser": "player-1", "at_s": 180.0},
     "damage": {"player-1": {"wheels": [1.0, 1.0, 1.0, 1.0], "weapon": 0.9, "drive": 1.0,
                             "core": 0.8,
                             "armour": {"front": 0.6, "sides": 0.9, "rear": 1.0, "top": 1.0}}},
     "scrap": {"player-1": 0},
     "scrap_breakdown": {"player-1": {"base": 150, "damage": 60, "survivor": 75, "flawless": 0,
                                      "total": 285}}}
    """

    private static func check(_ what: String, _ passed: Bool, detail: String = "") {
        if passed {
            passes += 1
            say("PASS  \(what)")
        } else {
            failures.append(detail.isEmpty ? what : "\(what) [\(detail)]")
            say("FAIL  \(what)\(detail.isEmpty ? "" : " [\(detail)]")")
        }
    }

    /// Something that is not wrong yet. The thirteen new parts are D1's and D2's, landing in this
    /// same wave: a ladder id with no catalogue entry is a warning now and a pass once they land.
    private static func warn(_ what: String) {
        warnings.append(what)
        say("WARN  \(what)")
    }

    private static func say(_ line: String) {
        print("[career] \(line)")
        spikeLog.info("[career] \(line, privacy: .public)")
    }
}
