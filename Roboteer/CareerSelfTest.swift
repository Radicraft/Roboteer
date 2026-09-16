//
//  CareerSelfTest.swift
//  There is no test target in this project, so the career engine carries its own. Launch with
//  `-careerSelfTest` and it runs a scripted season through `CareerEngine` before the first screen
//  appears, asserting the invariants of docs/stage5-spec.md sections 2 and 6 and printing one
//  PASS or FAIL line per check plus a summary.
//
//  Everything it touches is pure: no SwiftData, no SwiftUI, no arena. It is safe to run at launch
//  and it changes nothing.
//

import Foundation

enum CareerSelfTest {

    private static var passes = 0
    private static var failures: [String] = []

    static func runIfRequested() {
        guard ArenaHost.hasLaunchFlag("-careerSelfTest") else { return }
        run()
    }

    @discardableResult
    static func run() -> Bool {
        passes = 0
        failures = []
        say("career self test starting")

        checkCatalogue()
        checkBlueprintDrip()
        checkBuilds()
        checkPrices()
        checkRepairBill()
        checkSeasonShape()
        checkScriptedSeason()
        checkRivalMemory()
        checkTheWall()
        checkHouseBots()
        checkHouseBotChoice()
        checkOpponentHeads()
        checkNextFightCard()
        checkSeasonSummary()

        if failures.isEmpty {
            say("career self test: ALL PASS (\(passes) checks)")
            return true
        }
        say("career self test: \(failures.count) FAILED of \(passes + failures.count)")
        for line in failures { say("  FAILED: \(line)") }
        return false
    }

    // MARK: - Checks

    private static func checkCatalogue() {
        let catalogue = CareerCatalogue.shared
        check("the catalogue has five tiers", catalogue.tiers.count == 5)
        check("the catalogue has eight rivals", catalogue.rivals.count == 8)
        check("the catalogue has five bosses", catalogue.bosses.count == 5)
        check("every price factor is present", ["chassis", "weapon", "drive", "armour", "utility"]
            .allSatisfy { catalogue.economy.factor($0) > 0 })
        check("the write off threshold is 0.7", abs(catalogue.economy.writeOffThreshold - 0.7) < 0.0001)
        check("scrap for parts is 0.4", abs(catalogue.economy.scrapForParts - 0.4) < 0.0001)

        for tier in CareerTier.allCases {
            guard let entry = catalogue.tier(tier) else {
                check("tier \(tier.rawValue) is in the catalogue", false)
                continue
            }
            check("tier \(tier.rawValue) index agrees with the enum", entry.index == tier.index)
            check("tier \(tier.rawValue) has a fee and a purse", entry.entryFee > 0 && entry.purse > 0)
            check("tier \(tier.rawValue) arenas all exist",
                  entry.arenas.allSatisfy { Catalogue.shared.arena($0) != nil })
            check("tier \(tier.rawValue) is three rounds", entry.rounds == CareerBracket.rounds)
            check("tier \(tier.rawValue) final pays three times",
                  CareerEngine.purse(tier, round: entry.rounds - 1) == entry.purse * 3)
        }

        let capacities = CareerTier.allCases.map { CareerEngine.garageCapacity($0) }
        check("garage capacity grows 1 to 5 with the tier", capacities == [1, 2, 3, 4, 5])
        check("the free tiers are Scrapyard and Regional",
              catalogue.tiers.filter(\.free).map(\.id).sorted() == ["regional", "scrapyard"])
        check("the Championship alternates two arenas",
              catalogue.tier(.championship)?.arenas == ["furnace", "crush"])
        check("the Championship arena alternates by round",
              CareerEngine.arena(.championship, round: 0) == "furnace"
              && CareerEngine.arena(.championship, round: 1) == "crush")
    }

    private static func checkBlueprintDrip() {
        let catalogue = CareerCatalogue.shared
        var held = Set(catalogue.startingUnlocks)
        check("the starting unlocks are thirteen parts", catalogue.startingUnlocks.count == 13)
        check("a starting wedge, a flipper and steel are unlocked from the first minute",
              held.isSuperset(of: ["wedge", "flipper", "steel", "4wd", "srimech"]))

        var duplicated: [String] = []
        for entry in catalogue.tiers.sorted(by: { $0.index < $1.index }) {
            for part in entry.blueprints {
                if held.contains(part) { duplicated.append(part) }
                held.insert(part)
            }
        }
        check("no blueprint is handed out twice", duplicated.isEmpty)

        let parts = Catalogue.shared
        var every = Set(parts.chassis.map(\.id))
        every.formUnion(parts.drives.map(\.id))
        every.formUnion(parts.weapons.map(\.id))
        every.formUnion(parts.utilities.map(\.id))
        every.formUnion(parts.materials.map(\.id))
        check("every catalogue part is either a starting unlock or dripped", held == every)

        // The free portion: brief section 14 wants three or four weapons and two chassis earned
        // before the wall.
        let free = catalogue.tiers.filter(\.free).flatMap(\.blueprints)
        let weapons = free.filter { parts.weapon($0) != nil }
        let chassis = free.filter { parts.chassis($0) != nil }
        check("the free portion earns four weapons", weapons.count == 4)
        check("the free portion earns two chassis", chassis.count == 2)
        check("Scrapyard drips two weapons and one chassis over three wins",
              catalogue.tier(.scrapyard)?.blueprints.count == 3)
        check("Regional drips five parts over its wins",
              catalogue.tier(.regional)?.blueprints.count == 5)

        // The drip hands out one per win and everything that is left on the last one.
        let regional = catalogue.drip(tier: .regional, afterWins: 1)
        check("one Regional win is one blueprint", regional.count == 1)
        check("taking the Regional hands over the whole drip",
              catalogue.drip(tier: .regional, afterWins: 3).count == 5)
        check("a part earned at Regional says so",
              catalogue.tierThatUnlocks("tracks")?.id == "regional")
    }

    private static func checkBuilds() {
        for rival in CareerCatalogue.shared.rivals {
            check("rival \(rival.name) starts legal", BuildRules.isValid(rival.spec),
                  detail: BuildRules.errors(rival.spec).joined(separator: " "))
            check("rival \(rival.name) has three grudge lines", rival.grudgeLines.count == 3)
            check("rival \(rival.name) is not gold",
                  rival.liveryHex.lowercased() != "#f2c14e")
            for tier in CareerTier.allCases {
                let spec = CareerEngine.rivalSpec(rival, at: tier)
                check("rival \(rival.name) is legal at \(tier.rawValue)", BuildRules.isValid(spec),
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
    }

    private static func checkPrices() {
        let spec = BuildSpec.tinribs
        let value = CareerEngine.buildValue(spec)
        check("Tinribs is worth something", value > 0)

        // Value is the sum of the same part prices the bill uses, so a machine destroyed to nothing
        // costs exactly its own value to repair.
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

        // The threshold itself: just over seven tenths is a write off, just under is not.
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

    private static func checkSeasonShape() {
        let player = samplePlayer()
        let rivals = CareerCatalogue.shared.rivals
        let first = CareerEngine.startSeason(tier: .scrapyard, seed: 4242, player: player, rivals: rivals)
        let second = CareerEngine.startSeason(tier: .scrapyard, seed: 4242, player: player, rivals: rivals)
        check("the same seed draws the same season", first.encoded() == second.encoded())

        let other = CareerEngine.startSeason(tier: .scrapyard, seed: 99, player: player, rivals: rivals)
        check("a different seed draws a different season", other.encoded() != first.encoded())

        check("a season has eight entrants", first.entrants.count == CareerBracket.size)
        check("a season has seven ties", first.matches.count == CareerBracket.size - 1)
        check("exactly one entrant is the player", first.entrants.filter(\.isPlayer).count == 1)
        check("the player index points at the player", first.player?.isPlayer == true)
        check("every entrant id is different", Set(first.entrants.map(\.id)).count == first.entrants.count)
        check("every entrant is legal", first.entrants.allSatisfy { BuildRules.isValid($0.spec) })
        check("the first round is fully drawn",
              first.matches(inRound: 0).allSatisfy { $0.a != nil && $0.b != nil })
        check("the later rounds are not drawn yet",
              first.matches(inRound: 1).allSatisfy { $0.a == nil && $0.b == nil })
        check("the player has a first tie", first.playerMatch != nil)
        check("the player has an opponent", first.playerNextOpponent != nil)
        check("the season is not over before it starts", first.isOver == false)

        // Only three rivals are in the circuit at the Scrapyard, so the rest are filler.
        let scrapyardRivals = first.entrants.filter { $0.kind == .rival }
        check("only rivals who have entered the circuit appear at the Scrapyard",
              scrapyardRivals.allSatisfy { CareerCatalogue.shared.rival($0.rivalID)?.fromTier == .scrapyard })
        let masters = CareerEngine.startSeason(tier: .masters, seed: 7, player: player, rivals: rivals)
        check("the Masters field is all seven rivals",
              masters.entrants.filter { $0.kind == .rival }.count == 7)
    }

    private static func checkScriptedSeason() {
        let catalogue = CareerCatalogue.shared
        let player = samplePlayer()
        var tier = CareerTier.scrapyard
        var scrap = 500
        var blueprints = catalogue.startingUnlocks
        var winsThisTier = 0
        var capacity = CareerEngine.garageCapacity(tier)

        // Pay the fee and enter.
        let fee = CareerEngine.entryFee(tier)
        scrap -= fee
        check("the Scrapyard entry fee is fifty", fee == 50)
        var bracket = CareerEngine.startSeason(tier: tier, seed: 1234, player: player, rivals: catalogue.rivals)

        var earned: [String] = []
        var round = 0
        while let match = bracket.playerMatch {
            round = match.round
            let arena = CareerEngine.arena(tier, round: round)
            check("round \(round) is fought in an arena that exists", Catalogue.shared.arena(arena) != nil)
            bracket = CareerEngine.settlePlayerMatch(bracket, playerWon: true, note: "Knockout")
            winsThisTier += 1
            scrap += CareerEngine.purse(tier, round: round)
            let fresh = CareerEngine.newBlueprints(tier: tier, winsThisTier: winsThisTier, held: blueprints)
            earned.append(contentsOf: fresh)
            blueprints.append(contentsOf: fresh)
        }

        check("winning three ties takes the tier", winsThisTier == 3, detail: "\(winsThisTier)")
        check("the bracket knows the player took it", bracket.playerWonTier)
        check("the season is over", bracket.isOver)
        check("every tie in the bracket was settled", bracket.matches.allSatisfy(\.isSettled))
        check("the purse paid 120 + 120 + 360", scrap == 500 - 50 + 120 + 120 + 360, detail: "\(scrap)")
        check("taking the Scrapyard earned its whole drip", earned == catalogue.tier(.scrapyard)?.blueprints,
              detail: earned.joined(separator: ", "))
        check("the axe is now buildable", blueprints.contains("axe"))

        // Advance.
        tier = tier.next ?? tier
        capacity = CareerEngine.garageCapacity(tier)
        winsThisTier = 0
        check("the next tier is the Regional", tier == .regional)
        check("the Regional opens a second garage slot", capacity == 2)

        // Lose the Regional quarter final: the fee is gone and the season is over.
        let before = scrap
        scrap -= CareerEngine.entryFee(tier)
        var regional = CareerEngine.startSeason(tier: tier, seed: 77, player: player, rivals: catalogue.rivals)
        regional = CareerEngine.settlePlayerMatch(regional, playerWon: false, note: "Knockout")
        check("losing ends the season", regional.playerMatch == nil && regional.isOver)
        check("losing does not win the tier", regional.playerWonTier == false)
        check("losing still cost the entry fee", scrap == before - 120)
        check("the bracket still resolves to a champion", regional.matches.last?.winner != nil)
        check("the champion is not the player", regional.matches.last?.winner != regional.playerIndex)

        // The whole ladder, won end to end, unlocks everything.
        var held = Set(catalogue.startingUnlocks)
        for step in CareerTier.allCases {
            held.formUnion(CareerEngine.newBlueprints(tier: step, winsThisTier: 3, held: Array(held)))
        }
        check("winning every tier unlocks the whole part library",
              held == catalogue.unlocks(upTo: .masters))
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

        // Upgrades really do change the machine.
        let start = rival.spec
        let masters = CareerEngine.rivalSpec(rival, at: .masters)
        check("a rival's machine changes as it climbs", masters != start)
        check("a rival keeps its own name and livery",
              masters.name == rival.name && masters.liveryHex == rival.liveryHex)
    }

    // MARK: - The wall (P6, stage 6)

    /// The one rule the free half turns on: winning the Regional final while the game is locked
    /// keeps the player at Regional and offers the unlock once. Both sides are checked here with
    /// explicit gates, and the run's own `-locked` or `-unlocked` override is checked against the
    /// same answers, so the flag a tester passes is proved to do what they think it does.
    private static func checkTheWall() {
        let locked = Gates(isUnlocked: false)
        let open = Gates(isUnlocked: true)

        // Locked: the win stands, the tier does not move.
        let regionalLocked = CareerEngine.tierWon(at: .regional, gates: locked)
        check("a locked Regional final does not advance the tier", regionalLocked.advancedTo == nil)
        check("a locked Regional final is a wall and not a loss", regionalLocked.hitTheWall)
        check("the wall names the circuit and the full game in plain words",
              regionalLocked.sentence.contains(CareerTier.regional.title)
              && regionalLocked.sentence.contains(CareerTier.national.title)
              && regionalLocked.sentence.contains("full game"))
        check("no em dash reaches the player",
              !regionalLocked.sentence.contains("\u{2014}") && !regionalLocked.sentence.contains("\u{2013}"))
        check("the Scrapyard final still advances while the game is locked",
              CareerEngine.tierWon(at: .scrapyard, gates: locked).advancedTo == .regional)
        check("the free half is exactly Scrapyard and Regional",
              locked.tierAvailable(.scrapyard) && locked.tierAvailable(.regional)
              && !locked.tierAvailable(.national) && !locked.tierAvailable(.championship)
              && !locked.tierAvailable(.masters))
        check("the locked half reaches The Yard and The Grinder and no further",
              locked.arenaAvailable("yard") && locked.arenaAvailable("grinder")
              && !locked.arenaAvailable("drop_zone") && !locked.arenaAvailable("furnace")
              && !locked.arenaAvailable("crush") && !locked.arenaAvailable("coliseum"))
        check("a locked arena says what opens it",
              locked.lockedReason(.arena("furnace")).contains("full game"))

        // Unlocked: every final advances, and the last one is the last one.
        let regionalOpen = CareerEngine.tierWon(at: .regional, gates: open)
        check("an unlocked Regional final advances to National",
              regionalOpen.advancedTo == .national && !regionalOpen.hitTheWall)
        let everyAdvance = CareerTier.allCases.dropLast().allSatisfy { tier in
            CareerEngine.tierWon(at: tier, gates: open).advancedTo == tier.next
        }
        check("every circuit advances to the next one when the game is bought", everyAdvance)
        check("no circuit hits the wall when the game is bought",
              CareerTier.allCases.allSatisfy { !CareerEngine.tierWon(at: $0, gates: open).hitTheWall })
        let masters = CareerEngine.tierWon(at: .masters, gates: open)
        check("the Masters final is the end of the ladder",
              masters.wonTheLot && masters.advancedTo == nil && !masters.hitTheWall)
        check("the six arenas are all open when the game is bought",
              Catalogue.shared.arenas.allSatisfy { open.arenaAvailable($0.id) })

        // The launch override this run was actually given.
        switch StoreService.override {
        case .locked:
            let gates = Gates(isUnlocked: false)
            check("-locked holds the player at Regional",
                  gates.highestTier == .regional && gates.firstLockedTier == .national)
            check("-locked walls the Regional final",
                  CareerEngine.tierWon(at: .regional, gates: gates).hitTheWall)
        case .unlocked:
            let gates = Gates(isUnlocked: true)
            check("-unlocked opens every circuit",
                  gates.highestTier == .masters && gates.firstLockedTier == nil)
            check("-unlocked advances the Regional final",
                  CareerEngine.tierWon(at: .regional, gates: gates).advancedTo == .national)
        case .none:
            say("no store override on this run: pass -locked or -unlocked to check one")
        }
    }

    // MARK: - Wave G (brief v4 sections 3, 4 and 6)

    /// The house bot on duty. G2 owns the choice; what is checked here is the contract the card,
    /// the scouting report and the fight config all depend on, so it keeps holding when G2's
    /// version replaces the stub.
    private static func checkHouseBots() {
        let bosses = Set(CareerCatalogue.shared.bosses.map(\.id))
        check("there are bosses to put on duty", !bosses.isEmpty)

        for tier in CareerTier.allCases {
            for round in 0..<CareerBracket.rounds {
                let arena = CareerEngine.arena(tier, round: round)
                let bot = CareerEngine.houseBot(tier: tier, arena: arena)
                check("\(tier.rawValue) round \(round) has a house bot from the catalogue",
                      bosses.contains(bot.id), detail: bot.id)
                check("\(tier.rawValue) round \(round) house bot speed is a real speed",
                      bot.speed > 0 && bot.speed <= 1, detail: "\(bot.speed)")
                check("\(tier.rawValue) round \(round) house bot has a printable name",
                      CareerEngine.houseBotName(bot.id) == CareerCatalogue.shared.boss(bot.id)?.name)
            }
        }

        // Brief section 10 item 1: the Scrapyard's is THRESHER at half speed, and its scouting
        // line says what it does.
        let scrapyard = CareerEngine.houseBot(tier: .scrapyard, arena: "yard")
        check("the Scrapyard house bot is THRESHER at half speed",
              CareerEngine.houseBotName(scrapyard.id) == "THRESHER" && abs(scrapyard.speed - 0.5) < 0.0001,
              detail: "\(scrapyard.id) at \(scrapyard.speed)")

        let line = CareerEngine.houseBotLine(tier: .scrapyard, arena: "yard")
        check("the Scrapyard scouting line names the bot, the zone and the release",
              line.contains("THRESHER") && line.contains("corner zone") && line.contains("two minutes"),
              detail: line)
        check("the Scrapyard scouting line says it is the slow one", line.contains("half speed"))
        check("a full speed house bot does not claim to be slow",
              !CareerEngine.houseBotLine(tier: .masters, arena: "coliseum").contains("half speed"))
        check("no em dash reaches a house bot line",
              CareerTier.allCases.allSatisfy { tier in
                  let text = CareerEngine.houseBotLine(tier: tier, arena: CareerEngine.arena(tier, round: 0))
                  return !text.contains("\u{2014}") && !text.contains("\u{2013}")
              })
    }

    /// `bots[i].ai_skill` and `bots[i].temperament` (docs/wave-g-contracts.md, AI section).
    private static func checkOpponentHeads() {
        let five = ["brawler", "technician", "bully", "opportunist", "showboat"]
        check("the five temperaments are the contract's five",
              CareerEngine.temperaments.sorted() == five.sorted(),
              detail: CareerEngine.temperaments.joined(separator: ", "))
        check("the skill ids are the tier ids",
              CareerTier.allCases.allSatisfy { CareerEngine.aiSkill(for: $0) == $0.rawValue })

        // A rival keeps theirs for life: same answer every call, and the season seed cannot move it.
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
        check("a rival's temperament does not move with the season seed", rivalsStable)

        // A filler draws one from the season seed: always legal, and the field is not all the same.
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

        // Deterministic: the same id and the same seed give the same head on every device.
        check("the same filler and seed draw the same temperament",
              CareerEngine.temperament(fromID: "filler-3", salt: 77)
              == CareerEngine.temperament(fromID: "filler-3", salt: 77))
    }

    /// The next-fight card of brief v4 section 6, which is also what the fight config is built from.
    private static func checkNextFightCard() {
        let player = samplePlayer()
        let rivals = CareerCatalogue.shared.rivals
        let tier = CareerTier.regional
        let seed = 31337
        var bracket = CareerEngine.startSeason(tier: tier, seed: seed, player: player, rivals: rivals)

        var round = 0
        while bracket.playerMatch != nil, round < CareerBracket.rounds {
            guard let card = NextFight.make(
                tier: tier, bracket: bracket, seasonSeed: seed, record: nil,
                playerBotName: "Tinribs", repairsDue: 0) else {
                check("round \(round) has a next fight card", false)
                break
            }

            check("round \(round) card knows which round it is", card.round == round)
            check("round \(round) card names the round the way the brief does",
                  card.roundTitle == ["Quarter-final", "Semi-final", "Final"][round], detail: card.roundTitle)
            check("round \(round) card's arena exists", Catalogue.shared.arena(card.arena) != nil)
            check("round \(round) card's arena is the tier's arena for that round",
                  card.arena == CareerEngine.arena(tier, round: round))
            check("round \(round) card prints the entry fee", card.entryFee == CareerEngine.entryFee(tier))
            check("round \(round) card prints what a win pays", card.purse == CareerEngine.purse(tier, round: round))
            check("round \(round) card's purse is a real number", card.purse > 0)
            check("round \(round) card names the house bot",
                  !card.houseBotID.isEmpty && !card.houseBotName.isEmpty && !card.houseBotLine.isEmpty)
            check("round \(round) card carries the skill the arena is sent",
                  card.aiSkill == tier.rawValue)
            check("round \(round) card carries a legal temperament",
                  CareerEngine.temperaments.contains(card.temperament), detail: card.temperament)
            check("round \(round) card has something to say about the opponent",
                  !card.scoutingLine.isEmpty)
            check("round \(round) card has no grudge line with no history", card.grudgeLine.isEmpty)
            check("round \(round) card leaves no placeholder in the words",
                  !card.scoutingLine.contains("{player}") && !card.scoutingLine.contains("{bot}"))
            check("round \(round) card writes no em dash",
                  ![card.scoutingLine, card.houseBotLine, card.arenaName, card.roundTitle]
                      .contains { $0.contains("\u{2014}") || $0.contains("\u{2013}") })
            check("only the final says it is the final", card.isFinal == (round == CareerBracket.rounds - 1))

            bracket = CareerEngine.settlePlayerMatch(bracket, playerWon: true, note: "Knockout")
            round += 1
        }
        check("the card was checked in all three rounds", round == CareerBracket.rounds, detail: "\(round)")

        // Out of the season: there is no next fight, so the screen shows the summary instead.
        check("a finished season has no next fight card",
              NextFight.make(tier: tier, bracket: bracket, seasonSeed: seed, record: nil,
                             playerBotName: "Tinribs") == nil)
        var lost = CareerEngine.startSeason(tier: tier, seed: 8, player: player, rivals: rivals)
        lost = CareerEngine.settlePlayerMatch(lost, playerWon: false, note: "Knockout")
        check("a lost season has no next fight card",
              NextFight.make(tier: tier, bracket: lost, seasonSeed: 8, record: nil,
                             playerBotName: "Tinribs") == nil)
        check("no season at all has no next fight card",
              NextFight.make(tier: tier, bracket: nil, seasonSeed: 8, record: nil,
                             playerBotName: "Tinribs") == nil)

        // The repair bill is a charge, so it has to reach the card.
        let withBill = NextFight.make(
            tier: tier,
            bracket: CareerEngine.startSeason(tier: tier, seed: seed, player: player, rivals: rivals),
            seasonSeed: seed, record: nil, playerBotName: "Tinribs", repairsDue: 84)
        check("a machine's outstanding repair bill is on the card", withBill?.repairsDue == 84)
    }

    /// The season summary of brief v4 section 6: the record, the scrap and the blueprints.
    private static func checkSeasonSummary() {
        let tier = CareerTier.scrapyard
        let fee = CareerEngine.entryFee(tier)
        var tally = SeasonTally.opening(tier: tier, entryFee: fee)
        check("an opened tally knows it was opened", tally.opened)
        check("an opened tally remembers the fee", tally.entryFee == fee)
        check("an opened tally has fought nothing", tally.fights == 0 && tally.scrapEarned == 0)

        var held = CareerCatalogue.shared.startingUnlocks
        var expectedScrap = 0
        for round in 0..<CareerBracket.rounds {
            let purse = CareerEngine.purse(tier, round: round)
            let salvage = 10 * (round + 1)
            let fresh = CareerEngine.newBlueprints(tier: tier, winsThisTier: round + 1, held: held)
            held.append(contentsOf: fresh)
            expectedScrap += purse + salvage
            tally.record(won: true, purse: purse, salvage: salvage, blueprints: fresh,
                         tookTheTier: round == CareerBracket.rounds - 1)
        }

        check("the tally adds up every purse and every salvage", tally.scrapEarned == expectedScrap,
              detail: "\(tally.scrapEarned) of \(expectedScrap)")
        check("the tally counts three wins and no losses", tally.wins == 3 && tally.losses == 0)
        check("the tally knows the tier was taken", tally.tookTheTier)
        check("the tally keeps the tier the season was fought at", tally.tier == tier)
        check("the tally's net is what came in less what it cost to enter",
              tally.net == expectedScrap - fee)
        check("the tally holds the whole Scrapyard drip",
              tally.blueprints == CareerCatalogue.shared.tier(tier)?.blueprints,
              detail: tally.blueprints.joined(separator: ", "))
        check("the record line is written in words", tally.recordLine == "Won three, lost none.",
              detail: tally.recordLine)

        let lines = tally.summaryLines
        check("the summary is three lines", lines.count == 3)
        check("no summary line is empty", lines.allSatisfy { !$0.isEmpty })
        check("the summary says what came in and what it cost",
              lines[1].contains("\(expectedScrap)") && lines[1].contains("\(fee)"), detail: lines[1])
        check("the summary names the blueprints rather than their ids",
              lines[2].contains(CareerEngine.partName("axe")) && !lines[2].contains("vertical_spinner"),
              detail: lines[2])
        check("no em dash reaches the season summary",
              lines.allSatisfy { !$0.contains("\u{2014}") && !$0.contains("\u{2013}") })

        // A season that ended in the quarter final.
        var short = SeasonTally.opening(tier: .regional, entryFee: CareerEngine.entryFee(.regional))
        short.record(won: false, purse: 0, salvage: 24, blueprints: [], tookTheTier: false)
        check("a season lost in the first round is one loss", short.recordLine == "Won none, lost one.",
              detail: short.recordLine)
        check("a season lost still banks its salvage", short.scrapEarned == 24)
        check("a season lost says so about its blueprints",
              short.summaryLines[2] == "No new blueprints this season.")
        check("a season lost did not take the tier", !short.tookTheTier)

        // It is kept on the career as text, so it has to survive a round trip.
        check("a tally survives being written and read back",
              SeasonTally.decode(tally.encoded()) == tally)
        check("an empty string reads back as no tally", SeasonTally.decode("") == nil)
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

    /// Which house bot each tier and arena names, brief v4 sections 3 and 10 (agent G2). G5's
    /// `checkHouseBots()` above checks the contract the card and the fight config depend on;
    /// this checks the choice itself, and the Quick Fight toggle that can turn it off.
    private static func checkHouseBotChoice() {
        let ids = Set(CareerCatalogue.shared.bosses.map(\.id))
        for tier in CareerTier.allCases {
            for arena in ["yard", "grinder", "drop_zone", "furnace", "crush", "coliseum"] {
                let house = CareerEngine.houseBot(tier: tier, arena: arena)
                check("\(tier.rawValue) in \(arena) is guarded by a boss that exists",
                      ids.contains(house.id), detail: house.id)
                check("\(tier.rawValue) in \(arena) house bot speed is sane",
                      house.speed > 0 && house.speed <= 1.0, detail: "\(house.speed)")
            }
        }
        check("Scrapyard gets THRESHER at half speed",
              CareerEngine.houseBot(tier: .scrapyard, arena: "yard") == ("thresher", 0.5))
        check("Regional gets CINDER at full speed",
              CareerEngine.houseBot(tier: .regional, arena: "grinder") == ("cinder", 1.0))
        check("National fields BANDSAW or GRUDGE",
              ["bandsaw", "grudge"].contains(CareerEngine.houseBot(tier: .national, arena: "drop_zone").id))
        check("Championship fields ANVIL or THRESHER",
              ["anvil", "thresher"].contains(CareerEngine.houseBot(tier: .championship, arena: "furnace").id))
        check("the Crush pairs with THRESHER at Championship",
              CareerEngine.houseBot(tier: .championship, arena: "crush").id == "thresher")
        check("Masters pairs the boss to the arena",
              CareerEngine.bossForArena("drop_zone") == "cinder"
              && CareerEngine.bossForArena("furnace") == "grudge"
              && CareerEngine.bossForArena("crush") == "thresher"
              && CareerEngine.bossForArena("coliseum") == "anvil")
        check("the same tier and arena always name the same house bot",
              CareerEngine.houseBot(tier: .masters, arena: "coliseum")
              == CareerEngine.houseBot(tier: .masters, arena: "coliseum"))

        // Quick Fight: the toggle is on from Regional up and off at Scrapyard, until the player
        // says otherwise, and what it says is remembered.
        check("a quick fight at Scrapyard has no house bot by default",
              QuickFightChoice().houseBotOn(tier: .scrapyard) == false)
        check("a quick fight above Scrapyard has one by default",
              CareerTier.allCases.filter { $0 != .scrapyard }
                  .allSatisfy { QuickFightChoice().houseBotOn(tier: $0) })
        var chosen = QuickFightChoice()
        chosen.houseBot = false
        check("a quick fight remembers the toggle being turned off",
              chosen.houseBotOn(tier: .masters) == false)
    }

    private static func check(_ what: String, _ passed: Bool, detail: String = "") {
        if passed {
            passes += 1
            say("PASS  \(what)")
        } else {
            failures.append(detail.isEmpty ? what : "\(what) [\(detail)]")
            say("FAIL  \(what)\(detail.isEmpty ? "" : " [\(detail)]")")
        }
    }

    private static func say(_ line: String) {
        print("[career] \(line)")
        spikeLog.info("[career] \(line, privacy: .public)")
    }
}
