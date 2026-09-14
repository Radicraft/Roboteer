//
//  BotBuild.swift
//  The saved machine. One SwiftData model per bot in the garage (docs/stage4-spec.md section 7).
//  It stores part ids only: every number about a part comes from the catalogue at read time, so a
//  catalogue change reprices every saved bot without a migration.
//

import Foundation
import SwiftData

@Model
final class BotBuild {

    var name: String = "New bot"

    // Part ids, all from `Shared/parts.json`.
    var chassisID: String = "wedge"
    var driveID: String = "4wd"
    var weaponID: String = "flipper"
    var utilities: [String] = ["srimech"]

    // Armour, four faces of material plus thickness.
    var frontMaterial: String = "steel"
    var frontThickness: Int = 2
    var sidesMaterial: String = "hdpe"
    var sidesThickness: Int = 2
    var rearMaterial: String = "polycarbonate"
    var rearThickness: Int = 1
    var topMaterial: String = "titanium"
    var topThickness: Int = 1

    var liveryHex: String = LiveryPresets.defaultHex

    /// The FightConfig `damage` block as JSON text, carried between fights. Empty means pristine.
    var damageJSON: String = ""

    // Record.
    var fights: Int = 0
    var wins: Int = 0
    var kos: Int = 0
    /// The name of the machine that last killed this one. Empty while it has never been killed.
    var killedBy: String = ""

    /// Beyond economical repair (docs/stage5-spec.md section 1). A written off machine stays on
    /// the shelf as a record but can never fight again.
    var isWrittenOff: Bool = false
    /// When it was written off, or nil while it is still a going concern.
    var retiredAt: Date?

    var createdAt: Date = Date()
    /// Which build the garage fights with. Capacity is one in Stage 4, so exactly one is selected.
    var isSelected: Bool = false

    init(spec: BuildSpec = .defaultWedge, createdAt: Date = Date(), isSelected: Bool = false) {
        self.createdAt = createdAt
        self.isSelected = isSelected
        apply(spec)
    }

    // MARK: - Spec

    /// The whole bot as a value, which is what the rules and the builder work on.
    var spec: BuildSpec {
        get {
            BuildSpec(
                name: name,
                chassis: chassisID,
                drive: driveID,
                weapon: weaponID,
                utilities: utilities,
                armour: [
                    "front": ArmourFaceSpec(material: frontMaterial, thickness: frontThickness),
                    "sides": ArmourFaceSpec(material: sidesMaterial, thickness: sidesThickness),
                    "rear": ArmourFaceSpec(material: rearMaterial, thickness: rearThickness),
                    "top": ArmourFaceSpec(material: topMaterial, thickness: topThickness)
                ],
                liveryHex: liveryHex
            )
        }
        set { apply(newValue) }
    }

    func apply(_ spec: BuildSpec) {
        name = spec.name
        chassisID = spec.chassis
        driveID = spec.drive
        weaponID = spec.weapon
        utilities = spec.utilities
        if let plate = spec.armour["front"] { frontMaterial = plate.material; frontThickness = plate.thickness }
        if let plate = spec.armour["sides"] { sidesMaterial = plate.material; sidesThickness = plate.thickness }
        if let plate = spec.armour["rear"] { rearMaterial = plate.material; rearThickness = plate.thickness }
        if let plate = spec.armour["top"] { topMaterial = plate.material; topThickness = plate.thickness }
        liveryHex = spec.liveryHex
    }

    // MARK: - Reading

    var totalWeight: Double { BuildRules.totalWeight(spec) }
    var isValid: Bool { BuildRules.isValid(spec) }

    /// "Wedge, 4WD, Flipper" for a list row.
    var partsLine: String {
        let catalogue = Catalogue.shared
        let parts = [
            catalogue.chassis(chassisID)?.name ?? chassisID,
            catalogue.drive(driveID)?.name ?? driveID,
            catalogue.weapon(weaponID)?.name ?? weaponID
        ]
        return parts.joined(separator: ", ")
    }

    /// "No fights yet." or "4 fights, 2 wins, 1 knockout."
    var recordLine: String {
        guard fights > 0 else { return "No fights yet." }
        var parts = ["\(fights) \(fights == 1 ? "fight" : "fights")", "\(wins) \(wins == 1 ? "win" : "wins")"]
        if kos > 0 { parts.append("\(kos) \(kos == 1 ? "knockout" : "knockouts")") }
        return parts.joined(separator: ", ") + "."
    }

    // MARK: - The bridge shape

    /// Exactly the `FightConfig.bots[i]` shape of docs/bridge-spec.md, plus `livery`
    /// (docs/stage4-spec.md section 1). Numbers that must stay floats are Doubles here and
    /// `JSONText` keeps them floats on the wire.
    func toBotConfig(id: String, controller: String) -> [String: Any] {
        var armour: [String: Any] = [:]
        for face in Catalogue.shared.faces {
            guard let plate = spec.armour[face.id] else { continue }
            armour[face.id] = ["material": plate.material, "thickness": plate.thickness]
        }
        return [
            "id": id,
            "name": name,
            "controller": controller,
            "chassis": chassisID,
            "drive": driveID,
            "weapon": weaponID,
            "utility": utilities,
            "armour": armour,
            "livery": liveryHex,
            "damage": damageDictionary
        ]
    }

    /// How many condition entries the arena reports for this drive: one per wheel, or one per
    /// track side.
    var conditionCount: Int {
        Catalogue.shared.drive(driveID)?.conditionCount ?? 4
    }

    /// The saved damage, rebuilt strictly so every value is a Double of the right shape. A missing
    /// or unreadable `damageJSON` gives a pristine machine.
    var damageDictionary: [String: Any] {
        BotBuild.damageDictionary(from: damageJSON, conditionCount: conditionCount)
    }

    static func damageDictionary(from json: String, conditionCount: Int) -> [String: Any] {
        let root = json.isEmpty ? nil : JSONValue.parse(json)

        var wheels = (root?["wheels"]?.items ?? []).compactMap { $0.doubleValue }
        if wheels.count > conditionCount { wheels = Array(wheels.prefix(conditionCount)) }
        while wheels.count < conditionCount { wheels.append(1.0) }

        func condition(_ key: String, in parent: JSONValue?) -> Double {
            parent?[key]?.doubleValue ?? 1.0
        }

        let armourValue = root?["armour"]
        return [
            "wheels": wheels,
            "weapon": condition("weapon", in: root),
            "armour": [
                "front": condition("front", in: armourValue),
                "sides": condition("sides", in: armourValue),
                "rear": condition("rear", in: armourValue),
                "top": condition("top", in: armourValue)
            ],
            "drive": condition("drive", in: root),
            "core": condition("core", in: root)
        ]
    }

    /// Repair: back to a pristine machine before the next fight.
    func repair() {
        damageJSON = ""
    }
}

// MARK: - The garage

enum Garage {

    /// The build the player fights with. Capacity is one in Stage 4, so this is nearly always the
    /// only build there is, but the rule is written for Stage 5's garage.
    static func selected(from builds: [BotBuild]) -> BotBuild? {
        builds.first { $0.isSelected } ?? builds.first
    }

    static func select(_ build: BotBuild, in builds: [BotBuild]) {
        for other in builds {
            other.isSelected = (other.persistentModelID == build.persistentModelID)
        }
    }

    /// First launch: the Stage 3 fixture bot becomes the first build, named Tinribs.
    /// `-build <name>` then selects a build by name, for QA.
    static func prepare(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<BotBuild>())) ?? []
        var builds = existing

        if builds.isEmpty {
            let first = BotBuild(spec: .tinribs, isSelected: true)
            assert(BuildRules.isValid(first.spec), "the Stage 3 fixture bot must pass the Stage 4 rules")
            context.insert(first)
            try? context.save()
            builds = [first]
            spikeLog.info("garage seeded with \(first.name, privacy: .public), \(first.totalWeight, privacy: .public) kg")
        }

        if let wanted = ArenaHost.launchArgument("-build"),
           let match = builds.first(where: { $0.name.caseInsensitiveCompare(wanted) == .orderedSame }) {
            select(match, in: builds)
            try? context.save()
            spikeLog.info("-build selected \(match.name, privacy: .public)")
        } else if builds.allSatisfy({ !$0.isSelected }), let first = builds.first {
            first.isSelected = true
            try? context.save()
        }
    }
}
