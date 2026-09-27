//
//  CareerEngine.swift
//  The career, as pure functions. Nothing here touches SwiftData, SwiftUI or the arena: it takes
//  values in and gives values back, which is what lets `-careerSelfTest` run a whole scripted
//  season at launch and assert the invariants (docs/stage5-spec.md sections 2 and 6).
//
//  Every number comes from `CareerCatalogue`, which comes from `Shared/parts.json`.
//

import Foundation

// MARK: - Deterministic randomness

/// SplitMix64. Small, fast, and the same sequence on every device for a given seed, which is what
/// makes a season reproducible from `CareerState.currentSeasonSeed` alone.
struct SeededRandom: RandomNumberGenerator {

    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    init(seed: Int) {
        self.init(seed: UInt64(bitPattern: Int64(seed)))
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// 0 up to but not including `count`.
    mutating func index(_ count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int(next() % UInt64(count))
    }

    /// 0.0 up to but not including 1.0.
    mutating func fraction() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }

    mutating func pick<T>(_ items: [T]) -> T? {
        guard !items.isEmpty else { return nil }
        return items[index(items.count)]
    }

    mutating func shuffled<T>(_ items: [T]) -> [T] {
        var copy = items
        guard copy.count > 1 else { return copy }
        for position in stride(from: copy.count - 1, to: 0, by: -1) {
            let other = index(position + 1)
            copy.swapAt(position, other)
        }
        return copy
    }
}

// MARK: - The repair bill

struct RepairBill: Equatable {

    struct Item: Identifiable, Equatable {
        let id: String
        let label: String
        /// 0 to 1, how much condition this part lost.
        let lost: Double
        let cost: Int
    }

    var items: [Item] = []
    var total: Int = 0
    /// What the whole machine is worth, at the same price factors.
    var buildValue: Int = 0
    var isWriteOff: Bool = false
    /// What the wreck is worth if it is stripped instead of repaired.
    var scrapForParts: Int = 0

    var isPristine: Bool { total == 0 }

    /// "48 of 320 scrap", the one line the garage prints.
    var fractionOfValue: Double {
        buildValue > 0 ? Double(total) / Double(buildValue) : 0
    }
}

// MARK: - The engine

enum CareerEngine {

    static var catalogue: CareerCatalogue { CareerCatalogue.shared }
    static var parts: Catalogue { Catalogue.shared }

    // MARK: - Money

    static func entryFee(_ tier: CareerTier) -> Int { catalogue.tier(tier)?.entryFee ?? 0 }

    static func garageCapacity(_ tier: CareerTier) -> Int { catalogue.tier(tier)?.garageCapacity ?? 1 }

    static func arena(_ tier: CareerTier, round: Int) -> String {
        catalogue.tier(tier)?.arena(round: round) ?? "yard"
    }

    /// The purse for winning one tie. The final pays the tier's multiplier.
    static func purse(_ tier: CareerTier, round: Int) -> Int {
        guard let entry = catalogue.tier(tier) else { return 0 }
        let isFinal = round >= entry.rounds - 1
        return entry.purse * (isFinal ? entry.finalMultiplier : 1)
    }

    // MARK: - Prices

    /// What one part is worth: its price factor times its weight in kilograms.
    static func price(chassis id: String) -> Double {
        (parts.chassis(id)?.weight ?? 0) * catalogue.economy.factor("chassis")
    }

    static func price(drive id: String) -> Double {
        (parts.drive(id)?.weight ?? 0) * catalogue.economy.factor("drive")
    }

    static func price(weapon id: String) -> Double {
        (parts.weapon(id)?.weight ?? 0) * catalogue.economy.factor("weapon")
    }

    static func price(utility id: String) -> Double {
        (parts.utility(id)?.weight ?? 0) * catalogue.economy.factor("utility")
    }

    static func price(face id: String, in spec: BuildSpec) -> Double {
        BuildRules.weight(ofFace: id, in: spec) * catalogue.economy.factor("armour")
    }

    /// The whole machine at the same factors. This is what the write off threshold is measured
    /// against, so a cheap machine is written off by a smaller bill than an expensive one.
    static func buildValue(_ spec: BuildSpec) -> Int {
        var total = price(chassis: spec.chassis) + price(drive: spec.drive) + price(weapon: spec.weapon)
        for id in spec.utilities { total += price(utility: id) }
        for face in parts.faces { total += price(face: face.id, in: spec) }
        return Int(total.rounded())
    }

    // MARK: - The repair bill

    /// Condition lost times price, part by part (docs/stage5-spec.md section 6).
    ///
    /// The damage block the arena sends has six channels and the catalogue has five categories, so
    /// two of them are mapped rather than copied: the drive's loss is its own condition times the
    /// average of its wheels, because a bot on two good wheels of four is half a drive; and the
    /// utilities ride the chassis, so they take the core's loss.
    static func repairBill(for spec: BuildSpec, damage: FightResult.BotDamage?) -> RepairBill {
        var bill = RepairBill()
        bill.buildValue = buildValue(spec)
        bill.scrapForParts = Int((Double(bill.buildValue) * catalogue.economy.scrapForParts).rounded())

        guard let damage else {
            bill.isWriteOff = false
            return bill
        }

        func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

        let coreLost = 1 - clamp(damage.core)
        let weaponLost = 1 - clamp(damage.weapon)
        let wheelMean = damage.wheels.isEmpty
            ? 1.0
            : damage.wheels.map { clamp($0) }.reduce(0, +) / Double(damage.wheels.count)
        let driveLost = 1 - clamp(damage.drive) * wheelMean

        var running = 0.0

        func add(_ id: String, _ label: String, _ lost: Double, _ fullPrice: Double) {
            let cost = lost * fullPrice
            running += cost
            guard cost >= 0.5 else { return }
            bill.items.append(RepairBill.Item(id: id, label: label, lost: lost, cost: Int(cost.rounded())))
        }

        add("chassis", parts.chassis(spec.chassis)?.name ?? spec.chassis, coreLost, price(chassis: spec.chassis))
        add("drive", parts.drive(spec.drive)?.name ?? spec.drive, driveLost, price(drive: spec.drive))
        add("weapon", parts.weapon(spec.weapon)?.name ?? spec.weapon, weaponLost, price(weapon: spec.weapon))
        for face in parts.faces {
            let condition: Double
            switch face.id {
            case "front": condition = damage.armour.front
            case "sides": condition = damage.armour.sides
            case "rear": condition = damage.armour.rear
            case "top": condition = damage.armour.top
            default: condition = 1
            }
            add("armour_\(face.id)", "\(face.name) armour", 1 - clamp(condition), price(face: face.id, in: spec))
        }
        for id in spec.utilities {
            add("utility_\(id)", parts.utility(id)?.name ?? id, coreLost, price(utility: id))
        }

        bill.total = Int(running.rounded())
        bill.isWriteOff = bill.buildValue > 0
            && Double(bill.total) > catalogue.economy.writeOffThreshold * Double(bill.buildValue)
        return bill
    }

    // MARK: - Blueprints

    /// The ids this tier has handed over after so many wins, minus what is already held.
    static func newBlueprints(tier: CareerTier, winsThisTier: Int, held: [String]) -> [String] {
        let heldSet = Set(held)
        return catalogue.drip(tier: tier, afterWins: winsThisTier).filter { !heldSet.contains($0) }
    }

    /// "New blueprint: Axe" needs the part's own name, whichever list it is in.
    static func partName(_ id: String) -> String {
        if let part = parts.chassis(id) { return part.name }
        if let part = parts.drive(id) { return part.name }
        if let part = parts.weapon(id) { return part.name }
        if let part = parts.utility(id) { return part.name }
        if let part = parts.material(id) { return part.name }
        return id.replacingOccurrences(of: "_", with: " ").capitalizedFirst
    }

    // MARK: - Keeping a build legal

    /// Rival and filler builds are made by rules rather than by hand, so every one of them goes
    /// through this before it is allowed near the arena: the weapon and the chassis have to agree,
    /// a chassis that needs a srimech gets one, and armour is shaved a unit at a time until the
    /// machine is inside the weight budget.
    static func legalise(_ spec: BuildSpec) -> BuildSpec {
        var out = spec

        if let chassis = parts.chassis(out.chassis), let allowed = chassis.weaponsAllowed,
           !allowed.contains(out.weapon), let first = allowed.first {
            out.weapon = first
        }
        if let weapon = parts.weapon(out.weapon), let required = weapon.requiresChassis,
           required != out.chassis {
            out.chassis = required
        }
        if let chassis = parts.chassis(out.chassis), chassis.srimechRequired,
           !out.utilities.contains("srimech") {
            if out.utilities.count < 2 {
                out.utilities.insert("srimech", at: 0)
            } else {
                out.utilities[0] = "srimech"
            }
        }
        if let chassis = parts.chassis(out.chassis), !chassis.srimechRequired,
           out.utilities.count > 2 {
            out.utilities = Array(out.utilities.prefix(2))
        }
        out.utilities = Array(NSOrderedSet(array: out.utilities).compactMap { $0 as? String }.prefix(2))

        // Every face has to exist.
        for face in parts.faces where out.armour[face.id] == nil {
            out.armour[face.id] = ArmourFaceSpec(material: "hdpe", thickness: 1)
        }

        // Everything past this point is the weight budget. Armour gives first, then the second
        // utility, then the drive, then the weapon, so a machine keeps its character for as long
        // as it can. A Shell with a full body spinner is 75 kg of parts before a single plate, so
        // without the last two steps it can never be made legal at all.
        var guardrail = 0
        while BuildRules.totalWeight(out) > BuildRules.budget + 0.0001, guardrail < 96 {
            guardrail += 1
            if shaveArmour(&out) { continue }
            if dropUtility(&out) { continue }
            if lightenDrive(&out) { continue }
            if lightenWeapon(&out) { continue }
            break
        }
        return out
    }

    /// One unit off the heaviest face, or the lightest material once every face is down to one.
    private static func shaveArmour(_ spec: inout BuildSpec) -> Bool {
        let thickest = parts.faces
            .filter { (spec.armour[$0.id]?.thickness ?? 0) > 1 }
            .max { BuildRules.weight(ofFace: $0.id, in: spec) < BuildRules.weight(ofFace: $1.id, in: spec) }
        if let face = thickest, var plate = spec.armour[face.id] {
            plate.thickness -= 1
            spec.armour[face.id] = plate
            return true
        }
        guard let lightest = parts.materials.min(by: { $0.kgPerUnitArea < $1.kgPerUnitArea }),
              let face = parts.faces.first(where: { spec.armour[$0.id]?.material != lightest.id }) else { return false }
        spec.armour[face.id] = ArmourFaceSpec(material: lightest.id, thickness: 1)
        return true
    }

    /// The last utility that is not a srimech the chassis insists on.
    private static func dropUtility(_ spec: inout BuildSpec) -> Bool {
        let needsSrimech = parts.chassis(spec.chassis)?.srimechRequired ?? false
        guard let index = spec.utilities.lastIndex(where: { !(needsSrimech && $0 == "srimech") }) else { return false }
        spec.utilities.remove(at: index)
        return true
    }

    private static func lightenDrive(_ spec: inout BuildSpec) -> Bool {
        guard let lightest = parts.drives.min(by: { $0.weight < $1.weight }), lightest.id != spec.drive else { return false }
        spec.drive = lightest.id
        return true
    }

    /// The lightest weapon this chassis will take, which for the Shell is the ram.
    private static func lightenWeapon(_ spec: inout BuildSpec) -> Bool {
        let chassis = parts.chassis(spec.chassis)
        let candidates = parts.weapons.filter { weapon in
            if let allowed = chassis?.weaponsAllowed, !allowed.contains(weapon.id) { return false }
            if let required = weapon.requiresChassis, required != spec.chassis { return false }
            return true
        }
        guard let lightest = candidates.min(by: { $0.weight < $1.weight }), lightest.id != spec.weapon else { return false }
        spec.weapon = lightest.id
        return true
    }

    // MARK: - Rivals

    /// A rival's machine at a tier: its starting build with every upgrade up to and including that
    /// tier applied, in tier order, then legalised.
    static func rivalSpec(_ rival: CareerCatalogue.RivalEntry, at tier: CareerTier) -> BuildSpec {
        var spec = rival.spec
        for candidate in CareerTier.allCases where candidate.index <= tier.index {
            guard let swaps = rival.upgrades[candidate.rawValue] else { continue }
            for swap in swaps { spec = apply(swap, to: spec) }
        }
        spec.name = rival.name
        spec.liveryHex = rival.liveryHex
        return legalise(spec)
    }

    static func apply(_ swap: CareerCatalogue.Swap, to spec: BuildSpec) -> BuildSpec {
        var out = spec
        switch swap.slot {
        case "chassis": if let part = swap.part { out.chassis = part }
        case "drive": if let part = swap.part { out.drive = part }
        case "weapon": if let part = swap.part { out.weapon = part }
        case "utility_1", "utility_2":
            guard let part = swap.part else { break }
            let index = swap.slot == "utility_1" ? 0 : 1
            var fitted = out.utilities
            while fitted.count <= index { fitted.append(part) }
            fitted[index] = part
            out.utilities = fitted
        default:
            guard swap.slot.hasPrefix("armour_") else { break }
            let face = String(swap.slot.dropFirst("armour_".count))
            var plate = out.armour[face] ?? ArmourFaceSpec(material: "hdpe", thickness: 1)
            if let material = swap.material { plate.material = material }
            if let thickness = swap.thickness { plate.thickness = thickness }
            out.armour[face] = plate
        }
        return out
    }

    /// Which of the three lines a rival says, from what has happened between them.
    /// 0 is never met, 1 is they beat you last time, 2 is you beat them last time.
    static func grudgeLine(
        lines: [String],
        wins: Int,
        losses: Int,
        theyWonLast: Bool,
        playerName: String,
        botName: String
    ) -> String {
        guard !lines.isEmpty else { return "" }
        let index: Int
        if wins + losses == 0 {
            index = 0
        } else {
            index = theyWonLast ? 1 : 2
        }
        let line = lines[min(index, lines.count - 1)]
        return line
            .replacingOccurrences(of: "{player}", with: playerName)
            .replacingOccurrences(of: "{bot}", with: botName)
    }

    // MARK: - Filler entrants

    /// A machine made up for one season, at the tier's power band. Deterministic from the seed,
    /// so the same season always has the same field.
    static func fillerEntrant(
        index: Int,
        tier: CareerTier,
        rng: inout SeededRandom
    ) -> CareerEntrant {
        let entry = catalogue.tier(tier)
        let unlocked = fillerPool(tier: tier)

        let chassisPool = parts.chassis.filter { unlocked.contains($0.id) }
        let drivePool = parts.drives.filter { unlocked.contains($0.id) }
        let weaponPool = parts.weapons.filter { unlocked.contains($0.id) }
        let utilityPool = parts.utilities.filter { unlocked.contains($0.id) }
        let materialPool = parts.materials.filter { unlocked.contains($0.id) }

        let name = catalogue.fillerNames.isEmpty
            ? "Entrant \(index + 1)"
            : catalogue.fillerNames[(index &* 7 &+ rng.index(97)) % catalogue.fillerNames.count]
        let roboteer = catalogue.fillerRoboteers.isEmpty
            ? "Unknown"
            : catalogue.fillerRoboteers[(index &* 5 &+ rng.index(89)) % catalogue.fillerRoboteers.count]

        var spec = BuildSpec(
            name: name,
            chassis: rng.pick(chassisPool)?.id ?? "box",
            drive: rng.pick(drivePool)?.id ?? "4wd",
            weapon: rng.pick(weaponPool)?.id ?? "ram",
            utilities: [],
            armour: [:],
            liveryHex: fillerLivery(index: index, rng: &rng)
        )
        if let utility = rng.pick(utilityPool) { spec.utilities = [utility.id] }
        let base = rng.pick(materialPool)?.id ?? "hdpe"
        for face in parts.faces {
            spec.armour[face.id] = ArmourFaceSpec(material: base, thickness: 1)
        }
        spec = legalise(spec)

        // Grow the armour until the machine reaches the tier's power band, never past the budget.
        let band = entry?.powerBand ?? (low: 0.6, high: 0.8)
        let target = (band.low + rng.fraction() * max(0, band.high - band.low)) * BuildRules.budget
        var guardrail = 0
        while BuildRules.totalWeight(spec) < target, guardrail < 48 {
            guardrail += 1
            let face = parts.faces[rng.index(max(1, parts.faces.count))]
            guard var plate = spec.armour[face.id] else { continue }
            var candidate = spec
            if plate.thickness < parts.thicknessRange.upperBound {
                plate.thickness += 1
            } else if let heavier = materialPool.filter({ $0.kgPerUnitArea > (parts.material(plate.material)?.kgPerUnitArea ?? 0) }).min(by: { $0.kgPerUnitArea < $1.kgPerUnitArea }) {
                plate = ArmourFaceSpec(material: heavier.id, thickness: 1)
            } else {
                continue
            }
            candidate.armour[face.id] = plate
            guard BuildRules.totalWeight(candidate) <= BuildRules.budget + 0.0001 else { break }
            spec = candidate
        }

        return CareerEntrant(
            id: "filler-\(index)",
            name: name,
            roboteer: roboteer,
            liveryHex: spec.liveryHex,
            kind: .filler,
            spec: legalise(spec)
        )
    }

    /// The parts a made up entrant may be built from in a Series: everything the LADDER has
    /// opened by the Level a player reaches on winning that Series out (wave P), plus whatever a
    /// career starts out owning. That is what keeps a Series 5 filler carrying a Series 5 weapon
    /// now that there is no blueprint drip to read. An empty `progression` block falls back to the
    /// old union of the drips, so nothing here depends on the block being present.
    static func fillerPool(tier: CareerTier) -> Set<String> {
        let progression = catalogue.progression
        guard !progression.isEmpty else { return catalogue.unlocks(upTo: tier) }
        let ceiling = ProgressionEngine.seriesLevelCeiling(tier.index)
        var pool = Set(progression.levelRequired.filter { $0.value <= ceiling }.keys)
        pool.formUnion(catalogue.startingUnlocks)
        return pool
    }

    /// Never gold: gold is scrap and winner marks alone.
    private static func fillerLivery(index: Int, rng: inout SeededRandom) -> String {
        let palette = ["#5c6470", "#7d4b3a", "#365d4c", "#4b4f7a", "#8a6a4a", "#2f4f63", "#6d3b46", "#9aa0a6"]
        return palette[(index &+ rng.index(palette.count)) % palette.count]
    }

    // MARK: - Winning a tier

    /// What winning a tier's final does. Pure on purpose: it takes the gates rather than reading
    /// them, so the career self test can check both sides of the wall without a store.
    struct TierWin: Equatable {
        /// The Series the player moves up to, or nil when they stay where they are.
        var advancedTo: CareerTier?
        /// The win was real, but the next circuit is behind the wall.
        var hitTheWall = false
        /// True when this was the last circuit there is.
        var wonTheLot = false
        /// The plain sentence the assessment screen prints. Empty unless the wall was hit.
        var sentence = ""
    }

    /// Winning the Regional final while the game is locked must NOT advance the tier. The player
    /// keeps the win, keeps the purse and stays at Regional, and the game offers the unlock once
    /// (`Gates.shouldOfferAfterRegionalFinal`). When the game is bought later the next final
    /// advances normally, because this reads the gates every time rather than remembering.
    static func tierWon(at tier: CareerTier, gates: Gates) -> TierWin {
        var outcome = TierWin()
        guard let next = tier.next else {
            outcome.wonTheLot = true
            return outcome
        }
        guard gates.tierAvailable(next) else {
            outcome.hitTheWall = true
            outcome.sentence = "You have won the Series \(tier.index + 1) final. Series \(next.index + 1), the \(next.title), is in the full game, so you stay in Series \(tier.index + 1) for now and can replay any match you have won."
            return outcome
        }
        outcome.advancedTo = next
        return outcome
    }

    // MARK: - The season

    /// Eight entrants: the player, every rival in the circuit at this tier (up to seven of them)
    /// and filler machines for the rest, drawn into a seeded single elimination bracket.
    static func startSeason(
        tier: CareerTier,
        seed: Int,
        player: CareerEntrant,
        rivals: [CareerCatalogue.RivalEntry],
        rivalSpecs: [String: BuildSpec] = [:]
    ) -> CareerBracket {
        var rng = SeededRandom(seed: seed)

        var field: [CareerEntrant] = []
        let drawn = rng.shuffled(rivals.filter { $0.fromTier.index <= tier.index })
        for rival in drawn.prefix(CareerBracket.size - 1) {
            field.append(CareerEntrant(
                id: rival.id,
                name: rival.name,
                roboteer: rival.roboteer,
                liveryHex: rival.liveryHex,
                kind: .rival,
                spec: rivalSpecs[rival.id] ?? rivalSpec(rival, at: tier),
                rivalID: rival.id
            ))
        }
        var filler = 0
        while field.count < CareerBracket.size - 1 {
            field.append(fillerEntrant(index: filler, tier: tier, rng: &rng))
            filler += 1
        }

        var entrants = rng.shuffled(field)
        let slot = rng.index(CareerBracket.size)
        entrants.insert(player, at: min(slot, entrants.count))

        var matches: [CareerMatch] = []
        var count = CareerBracket.size / 2
        for round in 0..<CareerBracket.rounds {
            for slot in 0..<count {
                let a = round == 0 ? slot * 2 : nil
                let b = round == 0 ? slot * 2 + 1 : nil
                matches.append(CareerMatch(round: round, slot: slot, a: a, b: b, winner: nil))
            }
            count /= 2
        }

        return CareerBracket(
            tierRaw: tier.rawValue,
            seed: UInt64(bitPattern: Int64(seed)),
            entrants: entrants,
            matches: matches,
            playerIndex: entrants.firstIndex(where: { $0.isPlayer }) ?? 0
        )
    }

    /// Settle the player's tie, then settle every other tie in that round by simulation, then open
    /// the next round. Returns the bracket as it now stands.
    static func settlePlayerMatch(
        _ bracket: CareerBracket,
        playerWon: Bool,
        note: String
    ) -> CareerBracket {
        var out = bracket
        guard let match = out.playerMatch,
              let index = out.matches.firstIndex(where: { $0.round == match.round && $0.slot == match.slot }),
              let opponent = match.opponent(of: out.playerIndex) else { return out }

        out.matches[index].winner = playerWon ? out.playerIndex : opponent
        out.matches[index].note = note
        out = simulate(out, round: match.round)
        out = openNextRound(out, after: match.round)
        // Knocked out: the tournament carries on without the player and a champion is still
        // crowned, which is what the bracket screen shows after a loss.
        if out.playerMatch == nil {
            out = finishSeason(out, from: match.round + 1)
        }
        return out
    }

    /// Run every remaining round out by simulation.
    static func finishSeason(_ bracket: CareerBracket, from round: Int) -> CareerBracket {
        var out = bracket
        var current = max(0, round)
        while current < CareerBracket.rounds {
            out = simulate(out, round: current)
            out = openNextRound(out, after: current)
            current += 1
        }
        return out
    }

    /// Every unsettled tie in a round, decided by the machines and the season seed and nothing else.
    static func simulate(_ bracket: CareerBracket, round: Int) -> CareerBracket {
        var out = bracket
        for index in out.matches.indices where out.matches[index].round == round && !out.matches[index].isSettled {
            guard let a = out.matches[index].a, let b = out.matches[index].b else { continue }
            var rng = SeededRandom(seed: UInt64(bitPattern: Int64(out.seed)) &+ UInt64(index &+ 1) &* 0x2545F491)
            let scoreA = power(out.entrants[a].spec) + rng.fraction() * 0.5
            let scoreB = power(out.entrants[b].spec) + rng.fraction() * 0.5
            let winner = scoreA >= scoreB ? a : b
            out.matches[index].winner = winner
            out.matches[index].note = rng.fraction() < 0.55 ? "Knockout" : "Judges decision"
        }
        return out
    }

    /// Fill the next round's ties from the winners of this one.
    static func openNextRound(_ bracket: CareerBracket, after round: Int) -> CareerBracket {
        var out = bracket
        let next = round + 1
        guard next < CareerBracket.rounds else { return out }
        for index in out.matches.indices where out.matches[index].round == next {
            let slot = out.matches[index].slot
            let feederA = CareerBracket.matchIndex(round: round, slot: slot * 2)
            let feederB = CareerBracket.matchIndex(round: round, slot: slot * 2 + 1)
            guard out.matches.indices.contains(feederA), out.matches.indices.contains(feederB) else { continue }
            out.matches[index].a = out.matches[feederA].winner
            out.matches[index].b = out.matches[feederB].winner
        }
        return out
    }

    /// How dangerous a machine is, 0 to 1 ish. Only used to settle the ties the player is not in,
    /// so it is a comparison rather than a simulation: the arena is the authority on real fights.
    static func power(_ spec: BuildSpec) -> Double {
        let weapon = parts.weapon(spec.weapon)
        let drive = parts.drive(spec.drive)
        let hit = Double(weapon?.powerHitPips ?? 3) / 5.0
        let reach = Double(weapon?.reachPips ?? 3) / 5.0
        let mobility = Double((drive?.speedPips ?? 3) + (drive?.pushPips ?? 3)) / 10.0
        let armour = min(1, BuildRules.armourWeight(spec) / 30.0)
        return 0.34 * hit + 0.12 * reach + 0.2 * mobility + 0.34 * armour
    }

    // MARK: - Wave G: the house bot and the opponent's head (brief v4 sections 3, 4 and 6)

    /// Which house bot is on duty, and how fast it runs (brief v4 sections 3 and 10, agent G2).
    ///
    /// One per fight, named in `rules.enforcer` with `rules.enforcer_speed` beside it. It guards
    /// the marked corner all fight and is released at the endgame; it is never an entrant, so
    /// nothing here touches the bracket, the purse or the scoring.
    ///
    /// Where a tier has a choice of two, the arena decides, so that the scouting report and the
    /// fight always name the same machine: GRUDGE burns in the Furnace, THRESHER squeezes in the
    /// Crush. Scrapyard's THRESHER runs at half speed, which is how the first tier teaches the
    /// corner rule without ending anyone's career with it.
    ///
    /// `CareerFightView` (agent G5) puts the pair into the rules dictionary it sends:
    /// `let house = CareerEngine.houseBot(tier: tier, arena: arena)`, then
    /// `rules["enforcer"] = house.id` and `rules["enforcer_speed"] = house.speed`.
    static func houseBot(tier: CareerTier, arena: String) -> (id: String, speed: Double) {
        switch tier {
        case .scrapyard:
            return ("thresher", 0.5)
        case .regional:
            return ("cinder", 1.0)
        case .national:
            return (arena == "furnace" ? "grudge" : "bandsaw", 1.0)
        case .championship:
            return (arena == "crush" ? "thresher" : "anvil", 1.0)
        case .masters:
            return (bossForArena(arena), 1.0)
        }
    }

    /// The Masters pairing: whichever of the five suits the floor it is standing on.
    static func bossForArena(_ arena: String) -> String {
        switch arena {
        case "drop_zone": return "cinder"
        case "furnace": return "grudge"
        case "crush": return "thresher"
        case "coliseum": return "anvil"
        default: return "bandsaw"
        }
    }

    /// "THRESHER". The catalogue's own name, so a house bot is never printed as an id.
    static func houseBotName(_ id: String) -> String {
        catalogue.boss(id)?.name ?? id.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    /// What the house bot does, in the one sentence the scouting line wants (brief section 10
    /// item 1: "Its scouting line says what it does").
    static func houseBotLine(tier: CareerTier, arena: String, atSeconds: Int = 120) -> String {
        let bot = houseBot(tier: tier, arena: arena)
        let name = houseBotName(bot.id)
        let pace = bot.speed < 0.99 ? " at half speed" : ""
        return "\(name) guards the corner zone\(pace) and comes out hunting at \(clockWords(atSeconds))."
    }

    /// "two minutes", "one minute", "1:20": when the house bot comes out, in words when it is on
    /// the minute (wave B: the opener releases it at 1:20, owner decision 9).
    static func clockWords(_ seconds: Int) -> String {
        switch seconds {
        case 60: return "one minute"
        case 120: return "two minutes"
        case 180: return "three minutes"
        default: return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
    }

    // MARK: - The opponent's head

    /// The AI skill tier the shell sends as `bots[i].ai_skill` (contracts file, AI section). The
    /// ids are the tier ids, which is why this is a rename rather than a table.
    static func aiSkill(for tier: CareerTier) -> String { tier.rawValue }

    /// The five personalities of brief v4 section 4, in the order the contracts file names them.
    static let temperaments = ["brawler", "technician", "bully", "opportunist", "showboat"]

    /// The temperament the shell sends as `bots[i].temperament`.
    ///
    /// A rival keeps theirs for life: G3's `temperament` key in `Shared/parts.json` when it is
    /// there, and otherwise one derived from the rival's own id, which is stable across launches
    /// and devices. A filler draws one from the season seed, so the same season always fields the
    /// same heads.
    static func temperament(for entrant: CareerEntrant, seasonSeed: Int) -> String {
        if let rival = catalogue.rival(entrant.rivalID),
           temperaments.contains(rival.temperament) {
            return rival.temperament
        }
        let salt = entrant.kind == .filler ? seasonSeed : 0
        return temperament(fromID: entrant.id, salt: salt)
    }

    /// FNV-1a over the id, then one draw from the seeded generator. Swift's own `hashValue` is
    /// seeded per process and would give a rival a different head on every launch, so it is not
    /// used here.
    static func temperament(fromID id: String, salt: Int) -> String {
        var value: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in id.utf8 {
            value = (value ^ UInt64(byte)) &* 0x1000_0000_01B3
        }
        value = value &+ UInt64(bitPattern: Int64(salt))
        var rng = SeededRandom(seed: value)
        return temperaments[rng.index(temperaments.count)]
    }
}
