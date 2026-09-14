//
//  CareerModels.swift
//  The career's saved state (docs/stage5-spec.md section 1) and the value types the engine works
//  on. Three new SwiftData models plus the bracket, which is a plain Codable value kept as JSON
//  text inside `CareerState` so a tournament shape can change without a store migration.
//
//  Nothing here invents a number. Fees, purses, capacities, blueprint drips, rivals and bosses all
//  come from the `career`, `rivals`, `bosses` and `economy` blocks of `Shared/parts.json`.
//

import Foundation
import SwiftData

// MARK: - Tiers

/// The five circuits of brief section 9, in order.
enum CareerTier: String, CaseIterable, Codable, Identifiable {
    case scrapyard
    case regional
    case national
    case championship
    case masters

    var id: String { rawValue }

    /// 0 to 4. The catalogue carries the same number and the two are checked against each other
    /// by the self test.
    var index: Int { CareerTier.allCases.firstIndex(of: self) ?? 0 }

    var next: CareerTier? {
        let all = CareerTier.allCases
        let position = index + 1
        return position < all.count ? all[position] : nil
    }

    /// "Scrapyard". The catalogue's own name wins when it has one.
    var title: String {
        CareerCatalogue.shared.tier(self)?.name ?? rawValue.capitalizedFirst
    }

    static func named(_ raw: String) -> CareerTier {
        CareerTier(rawValue: raw) ?? .scrapyard
    }
}

// MARK: - The saved career

@Model
final class CareerState {

    /// One of the `CareerTier` raw values. Stored as text so an unknown tier reads back as
    /// Scrapyard rather than failing to decode.
    var tierRaw: String = CareerTier.scrapyard.rawValue

    /// The current season's bracket as `CareerBracket` JSON. Empty means no season has been
    /// entered yet, which is what the Enter button is for.
    var bracketJSON: String = ""

    var scrap: Int = 0
    var blueprints: [String] = []
    var garageCapacity: Int = 1

    var fightsPlayed: Int = 0
    var wins: Int = 0
    var championshipsWon: Int = 0

    /// The seed every deterministic thing in this season comes from: the draw, the filler bots
    /// and the AI results of the rounds the player is not in.
    var currentSeasonSeed: Int = 0

    /// Wins inside the current tier, which is the index into that tier's blueprint drip.
    var winsThisTier: Int = 0

    /// Set while a fight has been fought and its damage assessment has not been settled yet.
    var pendingAssessment: Bool = false

    var createdAt: Date = Date()

    init(tier: CareerTier = .scrapyard, scrap: Int = 0, seed: Int = 0) {
        self.tierRaw = tier.rawValue
        self.scrap = scrap
        self.currentSeasonSeed = seed
        self.blueprints = CareerCatalogue.shared.startingUnlocks
        self.garageCapacity = CareerCatalogue.shared.tier(tier)?.garageCapacity ?? 1
        self.createdAt = Date()
    }

    var tier: CareerTier {
        get { CareerTier.named(tierRaw) }
        set { tierRaw = newValue.rawValue }
    }

    /// The season in progress, or nil before the player has paid an entry fee.
    var bracket: CareerBracket? {
        get { CareerBracket.decode(bracketJSON) }
        set { bracketJSON = newValue?.encoded() ?? "" }
    }

    /// Every part id the player is allowed to fit.
    var unlocked: Set<String> { Set(blueprints) }

    func unlocks(_ partID: String) -> Bool { blueprints.contains(partID) }
}

// MARK: - Rivals

@Model
final class RivalRecord {

    /// The catalogue id, which is how a record is matched to its rival.
    var rivalID: String = ""
    var name: String = ""
    var roboteer: String = ""
    var liveryHex: String = "#3358a0"

    /// The rival's current machine as `BuildSpec` JSON. It is upgraded tier by tier and kept,
    /// so a rival met in the Masters is the same machine the player fought in the Scrapyard.
    var buildJSON: String = ""

    /// The tier this record was last upgraded to.
    var tierRaw: String = CareerTier.scrapyard.rawValue

    /// Results against the player, from the player's side: `winsVsPlayer` is fights this rival won.
    var winsVsPlayer: Int = 0
    var lossesVsPlayer: Int = 0

    var grudgeLines: [String] = []
    var lastMet: Date?
    /// True when the rival won the last time the two met, which is the line they open with.
    var lastResultWasTheirs: Bool = false
    /// The tier and round the two last met in, for the scouting line.
    var lastMetTier: String = ""
    var lastMetRound: Int = -1

    init(rivalID: String = "", name: String = "", roboteer: String = "", liveryHex: String = "#3358a0",
         spec: BuildSpec = .defaultWedge, tier: CareerTier = .scrapyard, grudgeLines: [String] = []) {
        self.rivalID = rivalID
        self.name = name
        self.roboteer = roboteer
        self.liveryHex = liveryHex
        self.buildJSON = spec.encoded()
        self.tierRaw = tier.rawValue
        self.grudgeLines = grudgeLines
    }

    var tier: CareerTier {
        get { CareerTier.named(tierRaw) }
        set { tierRaw = newValue.rawValue }
    }

    var spec: BuildSpec {
        get { BuildSpec.decode(buildJSON) ?? .defaultWedge }
        set { buildJSON = newValue.encoded() }
    }

    var hasMet: Bool { winsVsPlayer + lossesVsPlayer > 0 }
}

// MARK: - The fight log

@Model
final class FightLog {

    var date: Date = Date()
    var tierRaw: String = CareerTier.scrapyard.rawValue
    var round: Int = 0
    var opponentID: String = ""
    var opponentName: String = ""
    /// The player's machine, by name, because a written off bot may be gone by the time this is read.
    var botName: String = ""
    /// `ko`, `out_of_arena`, `judges`, `component_kill`, `timeout`.
    var outcome: String = ""
    var didWin: Bool = false
    var scrapEarned: Int = 0
    var repairCost: Int = 0
    var arena: String = "yard"

    /// The whole FightResult as it arrived, replay inputs included, as text.
    var resultJSON: String = ""
    /// Just the `replay` block, so a Stage 6 replay does not have to parse the whole result.
    var replayJSON: String = ""

    init() {}

    var tier: CareerTier {
        get { CareerTier.named(tierRaw) }
        set { tierRaw = newValue.rawValue }
    }

    /// "Regional, semi final. Won by knockout."
    var line: String {
        let roundName = CareerBracket.roundName(round, of: 3)
        let verb = didWin ? "Won" : "Lost"
        let how: String
        switch outcome {
        case "ko": how = "by knockout"
        case "out_of_arena": how = "out of the arena"
        case "component_kill": how = "on a dead core"
        case "judges": how = "on the judges"
        default: how = ""
        }
        return "\(tier.title), \(roundName). \(verb) \(how).".replacingOccurrences(of: "  ", with: " ")
    }
}

// MARK: - BuildSpec as text

/// `BuildSpec` and `ArmourFaceSpec` live in `BuildRules.swift`, and Swift will not synthesise
/// Codable for a type from another file, so the two conformances are written out here. They are
/// what put a rival's machine and a whole bracket into one string.
extension ArmourFaceSpec: Codable {

    enum CodingKeys: String, CodingKey {
        case material
        case thickness
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            material: try container.decodeIfPresent(String.self, forKey: .material) ?? "hdpe",
            thickness: try container.decodeIfPresent(Int.self, forKey: .thickness) ?? 1
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(material, forKey: .material)
        try container.encode(thickness, forKey: .thickness)
    }
}

extension BuildSpec: Codable {

    enum CodingKeys: String, CodingKey {
        case name
        case chassis
        case drive
        case weapon
        case utilities
        case armour
        case liveryHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "Machine",
            chassis: try container.decodeIfPresent(String.self, forKey: .chassis) ?? "box",
            drive: try container.decodeIfPresent(String.self, forKey: .drive) ?? "4wd",
            weapon: try container.decodeIfPresent(String.self, forKey: .weapon) ?? "ram",
            utilities: try container.decodeIfPresent([String].self, forKey: .utilities) ?? [],
            armour: try container.decodeIfPresent([String: ArmourFaceSpec].self, forKey: .armour) ?? [:],
            liveryHex: try container.decodeIfPresent(String.self, forKey: .liveryHex) ?? LiveryPresets.defaultHex
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(chassis, forKey: .chassis)
        try container.encode(drive, forKey: .drive)
        try container.encode(weapon, forKey: .weapon)
        try container.encode(utilities, forKey: .utilities)
        try container.encode(armour, forKey: .armour)
        try container.encode(liveryHex, forKey: .liveryHex)
    }
}

extension BuildSpec {

    func encoded() -> String {
        let encoder = JSONEncoder()
        // Keyed containers are unordered, so two identical values can encode to two different
        // strings. Sorting the keys makes the text itself deterministic, which is what lets a
        // season be compared and a store diff be meaningful.
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func decode(_ text: String) -> BuildSpec? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BuildSpec.self, from: data)
    }

    /// The `FightConfig.bots[i]` shape, for a bot that is not in the garage (a rival, a boss or a
    /// filler). Conditions are always pristine: only the player's machines carry damage between
    /// fights.
    func toBotConfig(id: String, controller: String, conditionCount: Int? = nil) -> [String: Any] {
        var armourOut: [String: Any] = [:]
        for face in Catalogue.shared.faces {
            guard let plate = armour[face.id] else { continue }
            armourOut[face.id] = ["material": plate.material, "thickness": plate.thickness]
        }
        let wheels = conditionCount ?? (Catalogue.shared.drive(drive)?.conditionCount ?? 4)
        return [
            "id": id,
            "name": name,
            "controller": controller,
            "chassis": chassis,
            "drive": drive,
            "weapon": weapon,
            "utility": utilities,
            "armour": armourOut,
            "livery": liveryHex,
            "damage": [
                "wheels": Array(repeating: 1.0, count: max(1, wheels)),
                "weapon": 1.0,
                "armour": ["front": 1.0, "sides": 1.0, "rear": 1.0, "top": 1.0],
                "drive": 1.0,
                "core": 1.0
            ]
        ]
    }

    /// "Box, 4WD, Saw" for a scouting card.
    var partsLine: String {
        let catalogue = Catalogue.shared
        return [
            catalogue.chassis(chassis)?.name ?? chassis,
            catalogue.drive(drive)?.name ?? drive,
            catalogue.weapon(weapon)?.name ?? weapon
        ].joined(separator: ", ")
    }

    /// "Steel 2 front, HDPE 2 sides, polycarbonate 1 rear, HDPE 1 top."
    var armourLine: String {
        let catalogue = Catalogue.shared
        let parts = catalogue.faces.compactMap { face -> String? in
            guard let plate = armour[face.id] else { return nil }
            let material = catalogue.material(plate.material)?.name ?? plate.material
            return "\(material) \(plate.thickness) \(face.id)"
        }
        return parts.joined(separator: ", ") + "."
    }
}

// MARK: - The bracket

/// One machine in a tournament: the player, a rival, or a filler entrant made up for this season.
struct CareerEntrant: Codable, Equatable, Identifiable {

    enum Kind: String, Codable {
        case player
        case rival
        case filler
    }

    var id: String
    var name: String
    var roboteer: String
    var liveryHex: String
    var kind: Kind
    var spec: BuildSpec
    /// For a rival, the catalogue id, so its record can be found. Empty otherwise.
    var rivalID: String = ""

    var isPlayer: Bool { kind == .player }
}

/// One tie. `a` and `b` are indices into `entrants` and are nil until the round before it has been
/// decided.
struct CareerMatch: Codable, Equatable {
    var round: Int
    var slot: Int
    var a: Int?
    var b: Int?
    var winner: Int?
    /// "Knockout at 34 s", written when the tie is settled.
    var note: String = ""

    var isSettled: Bool { winner != nil }

    func has(_ index: Int) -> Bool { a == index || b == index }

    func opponent(of index: Int) -> Int? {
        if a == index { return b }
        if b == index { return a }
        return nil
    }
}

/// Eight entrants, seven ties, three rounds. Matches are flat: 0 to 3 are the quarter finals,
/// 4 and 5 the semi finals, 6 the final. The ties of round r, slot s are fed by the winners of
/// round r - 1, slots 2s and 2s + 1.
struct CareerBracket: Codable, Equatable {

    static let size = 8
    static let rounds = 3

    var tierRaw: String
    var seed: UInt64
    var entrants: [CareerEntrant]
    var matches: [CareerMatch]
    var playerIndex: Int

    var tier: CareerTier { CareerTier.named(tierRaw) }

    // MARK: Reading

    static func matchIndex(round: Int, slot: Int) -> Int {
        // 4 ties in round 0, 2 in round 1, 1 in round 2.
        var base = 0
        var count = size / 2
        var r = 0
        while r < round {
            base += count
            count /= 2
            r += 1
        }
        return base + slot
    }

    func matches(inRound round: Int) -> [CareerMatch] {
        matches.filter { $0.round == round }.sorted { $0.slot < $1.slot }
    }

    /// The player's tie in the earliest round they have not won yet, or nil once the season is over.
    var playerMatch: CareerMatch? {
        matches.first { $0.has(playerIndex) && !$0.isSettled }
    }

    var playerNextOpponent: CareerEntrant? {
        guard let match = playerMatch, let index = match.opponent(of: playerIndex) else { return nil }
        return entrants.indices.contains(index) ? entrants[index] : nil
    }

    /// True once the player has lost a tie or won the final.
    var isOver: Bool {
        if playerMatch != nil { return false }
        return true
    }

    var playerWonTier: Bool {
        guard let final = matches.last, final.isSettled else { return false }
        return final.winner == playerIndex
    }

    /// How many ties the player has won in this season.
    var playerWins: Int {
        matches.filter { $0.isSettled && $0.winner == playerIndex }.count
    }

    var player: CareerEntrant? {
        entrants.indices.contains(playerIndex) ? entrants[playerIndex] : nil
    }

    func entrant(_ index: Int?) -> CareerEntrant? {
        guard let index, entrants.indices.contains(index) else { return nil }
        return entrants[index]
    }

    /// "quarter final", "semi final", "final".
    static func roundName(_ round: Int, of rounds: Int) -> String {
        switch rounds - round {
        case 1: return "final"
        case 2: return "semi final"
        case 3: return "quarter final"
        default: return "round \(round + 1)"
        }
    }

    var currentRoundName: String {
        CareerBracket.roundName(playerMatch?.round ?? CareerBracket.rounds - 1, of: CareerBracket.rounds)
    }

    // MARK: Text

    func encoded() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func decode(_ text: String) -> CareerBracket? {
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CareerBracket.self, from: data)
    }
}

// MARK: - The damage a machine is carrying

extension BotBuild {

    /// The `damageJSON` this machine came home with, in the same shape the arena reports, so the
    /// repair bill can be worked out in the garage as well as after a fight. A pristine machine
    /// reads back as full condition everywhere.
    var currentDamage: FightResult.BotDamage {
        let dictionary = damageDictionary
        var damage = FightResult.BotDamage()
        damage.wheels = (dictionary["wheels"] as? [Double]) ?? Array(repeating: 1.0, count: conditionCount)
        damage.weapon = (dictionary["weapon"] as? Double) ?? 1
        damage.drive = (dictionary["drive"] as? Double) ?? 1
        damage.core = (dictionary["core"] as? Double) ?? 1
        if let armour = dictionary["armour"] as? [String: Double] {
            damage.armour = FightResult.Armour(
                front: armour["front"] ?? 1,
                sides: armour["sides"] ?? 1,
                rear: armour["rear"] ?? 1,
                top: armour["top"] ?? 1
            )
        }
        return damage
    }

    /// A career entrant for this machine, for the bracket board.
    func careerEntrant(id: String = "player") -> CareerEntrant {
        CareerEntrant(
            id: id,
            name: name,
            roboteer: "You",
            liveryHex: liveryHex,
            kind: .player,
            spec: spec
        )
    }
}
