//
//  BuildRules.swift
//  The weight and validity rules of docs/stage4-spec.md section 1, in Swift. GDScript has the same
//  rules in `BuildRules` on the arena side and the two must agree: if one changes, change both and
//  change the spec first.
//
//  Every error is a plain sentence, ready to print. No em dashes.
//

import Foundation

/// One armour face as the builder holds it.
struct ArmourFaceSpec: Equatable, Hashable {
    var material: String
    var thickness: Int
}

/// A whole bot, as a value. `BotBuild` (SwiftData) stores one of these and the rules only ever see
/// this, so the rules can be run on a draft that has not been saved.
struct BuildSpec: Equatable {
    var name: String
    var chassis: String
    var drive: String
    var weapon: String
    var utilities: [String]
    var armour: [String: ArmourFaceSpec]
    var liveryHex: String

    func face(_ id: String) -> ArmourFaceSpec? { armour[id] }

    /// The default new bot: the cheapest honest machine that passes the rules.
    static let defaultWedge = BuildSpec(
        name: "New bot",
        chassis: "wedge",
        drive: "4wd",
        weapon: "flipper",
        utilities: ["srimech"],
        armour: [
            "front": ArmourFaceSpec(material: "steel", thickness: 2),
            "sides": ArmourFaceSpec(material: "hdpe", thickness: 2),
            "rear": ArmourFaceSpec(material: "polycarbonate", thickness: 1),
            "top": ArmourFaceSpec(material: "titanium", thickness: 1)
        ],
        liveryHex: LiveryPresets.defaultHex
    )

    /// Tinribs, the Stage 3 fixture player bot, which becomes the first build in the garage.
    static let tinribs = BuildSpec(
        name: "Tinribs",
        chassis: "wedge",
        drive: "4wd",
        weapon: "flipper",
        utilities: ["srimech"],
        armour: [
            "front": ArmourFaceSpec(material: "steel", thickness: 3),
            "sides": ArmourFaceSpec(material: "hdpe", thickness: 2),
            "rear": ArmourFaceSpec(material: "polycarbonate", thickness: 1),
            "top": ArmourFaceSpec(material: "titanium", thickness: 2)
        ],
        liveryHex: LiveryPresets.defaultHex
    )
}

/// Six liveries. Never gold: gold belongs to scrap and winner marks alone
/// (docs/stage2-art-direction.md, owner decision 2026-09-13).
enum LiveryPresets {
    static let all: [(name: String, hex: String)] = [
        ("Works blue", "#3358a0"),
        ("Signal red", "#b8362f"),
        ("Pit orange", "#d1662b"),
        ("Track green", "#2f7d5a"),
        ("Bone white", "#d8d5cc"),
        ("Gunmetal", "#4a5058")
    ]
    static let defaultHex = "#3358a0"
    static func name(for hex: String) -> String {
        all.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }?.name ?? "Custom"
    }
}

enum BuildRules {

    static let catalogue = Catalogue.shared

    // MARK: - Weight

    /// chassis + drive + weapon + utilities + every armour face.
    static func totalWeight(_ spec: BuildSpec) -> Double {
        partsWeight(spec) + armourWeight(spec)
    }

    static func partsWeight(_ spec: BuildSpec) -> Double {
        var total = catalogue.chassis(spec.chassis)?.weight ?? 0
        total += catalogue.drive(spec.drive)?.weight ?? 0
        total += catalogue.weapon(spec.weapon)?.weight ?? 0
        for id in spec.utilities {
            total += catalogue.utility(id)?.weight ?? 0
        }
        return total
    }

    static func armourWeight(_ spec: BuildSpec) -> Double {
        catalogue.faces.reduce(0) { running, face in
            guard let plate = spec.armour[face.id] else { return running }
            return running + catalogue.faceWeight(face: face.id, material: plate.material, thickness: plate.thickness)
        }
    }

    static func weight(ofFace id: String, in spec: BuildSpec) -> Double {
        guard let plate = spec.armour[id] else { return 0 }
        return catalogue.faceWeight(face: id, material: plate.material, thickness: plate.thickness)
    }

    static var budget: Double { catalogue.weightBudgetKg }

    static func remaining(_ spec: BuildSpec) -> Double { budget - totalWeight(spec) }

    // MARK: - Validity

    static func isValid(_ spec: BuildSpec) -> Bool { errors(spec).isEmpty }

    /// Plain sentences, in the order a builder would meet them.
    static func errors(_ spec: BuildSpec) -> [String] {
        var errors: [String] = []

        if spec.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Give the bot a name.")
        }

        guard let chassis = catalogue.chassis(spec.chassis) else {
            return errors + ["That chassis is not in the catalogue."]
        }
        guard let weapon = catalogue.weapon(spec.weapon) else {
            return errors + ["That weapon is not in the catalogue."]
        }
        if catalogue.drive(spec.drive) == nil {
            errors.append("That drive is not in the catalogue.")
        }

        // Weight.
        let over = totalWeight(spec) - budget
        if over > 0.0001 {
            errors.append("Over the weight budget by \(kilograms(over)).")
        }

        // Utilities.
        if spec.utilities.count > 2 {
            errors.append("Two utility slots at most.")
        }
        if Set(spec.utilities).count != spec.utilities.count {
            errors.append("Fit two different utilities.")
        }
        for id in spec.utilities where catalogue.utility(id) == nil {
            errors.append("That utility is not in the catalogue.")
        }
        if chassis.srimechRequired, !spec.utilities.contains("srimech") {
            errors.append("A \(chassis.name) needs a srimech.")
        }

        // Weapon and chassis have to agree, from both directions.
        if let allowed = chassis.weaponsAllowed, !allowed.contains(weapon.id) {
            errors.append("The \(chassis.name) only takes \(list(allowed)).")
        }
        if let required = weapon.requiresChassis, required != chassis.id {
            let name = catalogue.chassis(required)?.name ?? required
            errors.append("A \(weapon.name.lowercased()) only fits the \(name).")
        }

        // Armour.
        for face in catalogue.faces {
            guard let plate = spec.armour[face.id] else {
                errors.append("The \(face.id) face needs a material.")
                continue
            }
            if catalogue.material(plate.material) == nil {
                errors.append("The \(face.id) face needs a material.")
            }
            if !catalogue.thicknessRange.contains(plate.thickness) {
                errors.append("Armour thickness runs from \(catalogue.thicknessRange.lowerBound) to \(catalogue.thicknessRange.upperBound).")
            }
        }

        return errors
    }

    /// "a full body spinner or a ram", built from the catalogue names.
    private static func list(_ ids: [String]) -> String {
        let names = ids.map { id -> String in
            let name = catalogue.weapon(id)?.name.lowercased() ?? id.replacingOccurrences(of: "_", with: " ")
            return "a \(name)"
        }
        switch names.count {
        case 0: return "nothing"
        case 1: return names[0]
        case 2: return "\(names[0]) or \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " or " + (names.last ?? "")
        }
    }

    /// "6 kg", or "6.5 kg" when the number is not whole.
    static func kilograms(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded)) kg"
        }
        return String(format: "%.1f kg", rounded)
    }

    /// The same number without the unit, for the weight bar.
    static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }
}
