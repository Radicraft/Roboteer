//
//  Catalogue.swift
//  `Shared/parts.json` read once, in the order it was written. The catalogue is the contract
//  (docs/stage4-spec.md section 1): every part id, weight, stat and blurb lives in that file and
//  nowhere else. Godot reads the same bytes from `res://data/parts.json`.
//
//  Nothing here invents a number. The only derived values are the 1 to 5 stat pips, which are the
//  catalogue's own numbers scaled across the catalogue's own range so the bars mean something.
//

import Foundation

struct Catalogue {

    // MARK: - Parts

    struct Chassis: Identifiable, Equatable {
        let id: String
        let name: String
        let weight: Double
        let footprint: [Double]
        let height: Double
        let clearanceFront: Double
        let clearanceRear: Double
        let comHeight: Double
        let invertible: Bool
        let srimechRequired: Bool
        let invertedNote: String
        let mountWeapon: String
        let weaponsAllowed: [String]?
        let turnRateFactor: Double?
        let flipResistance: Double?
        let tipResistance: Double?
        let driveFragility: Double?
        let blurb: String
    }

    struct Drive: Identifiable, Equatable {
        let id: String
        let name: String
        let weight: Double
        let wheels: Int
        let tracks: Int
        let topSpeed: Double
        let turnRate: Double
        let pushForce: Double
        let traction: Double
        let wheelLoss: String
        let strafe: Bool
        let lateUnlock: Bool
        let blurb: String

        /// How many condition entries the arena reports for this drive. Tracks report one per side.
        var conditionCount: Int { tracks > 0 ? tracks : wheels }

        var speedPips = 3
        var turnPips = 3
        var pushPips = 3
    }

    struct Weapon: Identifiable, Equatable {
        let id: String
        let name: String
        let weight: Double
        let kind: String
        let reach: Double
        let heightBand: String
        let spinUpSeconds: Double?
        let resetSeconds: Double?
        let impulse: Double?
        let impulseBonus: Double?
        let dps: Double?
        let charges: Int?
        let fuelSeconds: Double?
        let disruptSeconds: Double?
        let clampForce: Double?
        let requiresChassis: String?
        let blurb: String

        var reachPips = 3
        var hitPips = 3
        var setupPips = 3

        /// One comparable "how hard does it hit" number, from whichever field the part has.
        var hitValue: Double {
            if let impulse { return impulse }
            if let dps { return dps * 2500 }
            if let impulseBonus { return impulseBonus * 100 }
            return 0
        }

        /// Seconds before this weapon is usable again. Zero means always ready.
        var setupSeconds: Double {
            if let spinUpSeconds { return spinUpSeconds }
            if let resetSeconds { return resetSeconds }
            return 0
        }
    }

    struct Utility: Identifiable, Equatable {
        let id: String
        let name: String
        let weight: Double
        let effect: String
        let blurb: String
    }

    struct Material: Identifiable, Equatable {
        let id: String
        let name: String
        let kgPerUnitArea: Double
        let versusSpinner: String
        let versusSawAxe: String

        /// Plain sentence for the picker row.
        var summary: String {
            "\(versusSpinner.capitalizedFirst) against spinners, \(versusSawAxe) against saws and axes."
        }
    }

    struct Face: Identifiable, Equatable {
        let id: String
        let area: Double

        /// "front" reads as "Front" on screen.
        var name: String { id.capitalizedFirst }
    }

    struct ArenaEntry: Identifiable, Equatable {
        let id: String
        let name: String
        let hazard: String
        let free: Bool
    }

    // MARK: - Contents

    let weightBudgetKg: Double
    let chassis: [Chassis]
    let drives: [Drive]
    let weapons: [Weapon]
    let utilities: [Utility]
    let materials: [Material]
    let faces: [Face]
    let arenas: [ArenaEntry]

    let thicknessRange: ClosedRange<Int>

    // MARK: - Lookups

    func chassis(_ id: String) -> Chassis? { chassis.first { $0.id == id } }
    func drive(_ id: String) -> Drive? { drives.first { $0.id == id } }
    func weapon(_ id: String) -> Weapon? { weapons.first { $0.id == id } }
    func utility(_ id: String) -> Utility? { utilities.first { $0.id == id } }
    func material(_ id: String) -> Material? { materials.first { $0.id == id } }
    func face(_ id: String) -> Face? { faces.first { $0.id == id } }
    func arena(_ id: String) -> ArenaEntry? { arenas.first { $0.id == id } }

    /// Every part id in the catalogue, in catalogue order: chassis, then drive, weapon, utility
    /// and armour material. The shop covers exactly this list (wave P) and the Level ladder is
    /// checked against it, so there is one definition of "every part" rather than five.
    var allPartIDs: [String] {
        chassis.map(\.id) + drives.map(\.id) + weapons.map(\.id)
            + utilities.map(\.id) + materials.map(\.id)
    }

    /// The weight of one armour face, per the catalogue's own formula.
    func faceWeight(face faceID: String, material materialID: String, thickness: Int) -> Double {
        guard let plate = face(faceID), let stuff = material(materialID) else { return 0 }
        return Double(thickness) * stuff.kgPerUnitArea * plate.area
    }

    // MARK: - Loading

    /// Loaded once. A missing or malformed `parts.json` is a build error, not a runtime state, so
    /// this traps in debug and falls back to an empty catalogue in release rather than crashing a
    /// player's app.
    static let shared: Catalogue = load()

    static func load() -> Catalogue {
        guard let url = Bundle.main.url(forResource: "parts", withExtension: "json"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let root = JSONValue.parse(text) else {
            assertionFailure("parts.json is missing from the bundle or did not parse")
            return Catalogue.empty
        }
        return Catalogue(root: root)
    }

    static let empty = Catalogue(
        weightBudgetKg: 100,
        chassis: [], drives: [], weapons: [], utilities: [],
        materials: [], faces: [], arenas: [],
        thicknessRange: 1...4
    )

    private init(
        weightBudgetKg: Double,
        chassis: [Chassis],
        drives: [Drive],
        weapons: [Weapon],
        utilities: [Utility],
        materials: [Material],
        faces: [Face],
        arenas: [ArenaEntry],
        thicknessRange: ClosedRange<Int>
    ) {
        self.weightBudgetKg = weightBudgetKg
        self.chassis = chassis
        self.drives = drives
        self.weapons = weapons
        self.utilities = utilities
        self.materials = materials
        self.faces = faces
        self.arenas = arenas
        self.thicknessRange = thicknessRange
    }

    private init(root: JSONValue) {
        weightBudgetKg = root["weight_budget_kg"]?.doubleValue ?? 100

        chassis = (root["chassis"]?.members ?? []).map { member in
            let value = member.value
            return Chassis(
                id: member.key,
                name: value["name"]?.stringValue ?? member.key,
                weight: value["weight"]?.doubleValue ?? 0,
                footprint: (value["footprint"]?.items ?? []).compactMap { $0.doubleValue },
                height: value["height"]?.doubleValue ?? 0,
                clearanceFront: value["clearance_front"]?.doubleValue ?? 0,
                clearanceRear: value["clearance_rear"]?.doubleValue ?? 0,
                comHeight: value["com_height"]?.doubleValue ?? 0,
                invertible: value["invertible"]?.boolValue ?? false,
                srimechRequired: value["srimech_required"]?.boolValue ?? false,
                invertedNote: value["inverted_note"]?.stringValue ?? "",
                mountWeapon: value["mount_weapon"]?.stringValue ?? "front",
                weaponsAllowed: value["weapons_allowed"].map { $0.stringItems },
                turnRateFactor: value["turn_rate_factor"]?.doubleValue,
                flipResistance: value["flip_resistance"]?.doubleValue,
                tipResistance: value["tip_resistance"]?.doubleValue,
                driveFragility: value["drive_fragility"]?.doubleValue,
                blurb: value["blurb"]?.stringValue ?? ""
            )
        }

        var loadedDrives = (root["drive"]?.members ?? []).map { member -> Drive in
            let value = member.value
            return Drive(
                id: member.key,
                name: value["name"]?.stringValue ?? member.key,
                weight: value["weight"]?.doubleValue ?? 0,
                wheels: value["wheels"]?.intValue ?? 0,
                tracks: value["tracks"]?.intValue ?? 0,
                topSpeed: value["top_speed"]?.doubleValue ?? 0,
                turnRate: value["turn_rate"]?.doubleValue ?? 0,
                pushForce: value["push_force"]?.doubleValue ?? 0,
                traction: value["traction"]?.doubleValue ?? 0,
                wheelLoss: value["wheel_loss"]?.stringValue ?? "",
                strafe: value["strafe"]?.boolValue ?? false,
                lateUnlock: value["late_unlock"]?.boolValue ?? false,
                blurb: value["blurb"]?.stringValue ?? ""
            )
        }
        Catalogue.scorePips(
            &loadedDrives,
            \.topSpeed, \.speedPips,
            \.turnRate, \.turnPips,
            \.pushForce, \.pushPips
        )
        drives = loadedDrives

        var loadedWeapons = (root["weapon"]?.members ?? []).map { member -> Weapon in
            let value = member.value
            return Weapon(
                id: member.key,
                name: value["name"]?.stringValue ?? member.key,
                weight: value["weight"]?.doubleValue ?? 0,
                kind: value["kind"]?.stringValue ?? "",
                reach: value["reach"]?.doubleValue ?? 0,
                heightBand: value["height_band"]?.stringValue ?? "",
                spinUpSeconds: value["spin_up_s"]?.doubleValue,
                resetSeconds: value["reset_s"]?.doubleValue,
                impulse: value["impulse"]?.doubleValue,
                impulseBonus: value["impulse_bonus"]?.doubleValue,
                dps: value["dps"]?.doubleValue,
                charges: value["charges"]?.intValue,
                fuelSeconds: value["fuel_s"]?.doubleValue,
                disruptSeconds: value["disrupt_s"]?.doubleValue,
                clampForce: value["clamp_force"]?.doubleValue,
                requiresChassis: value["requires_chassis"]?.stringValue,
                blurb: value["blurb"]?.stringValue ?? ""
            )
        }
        Catalogue.scoreWeaponPips(&loadedWeapons)
        weapons = loadedWeapons

        utilities = (root["utility"]?.members ?? []).map { member in
            let value = member.value
            return Utility(
                id: member.key,
                name: value["name"]?.stringValue ?? member.key,
                weight: value["weight"]?.doubleValue ?? 0,
                effect: value["effect"]?.stringValue ?? "",
                blurb: value["blurb"]?.stringValue ?? ""
            )
        }

        let armour = root["armour"]
        materials = (armour?["material"]?.members ?? []).map { member in
            let value = member.value
            return Material(
                id: member.key,
                name: value["name"]?.stringValue ?? member.key,
                kgPerUnitArea: value["kg_per_unit_area"]?.doubleValue ?? 0,
                versusSpinner: value["vs_spinner"]?.stringValue ?? "",
                versusSawAxe: value["vs_saw_axe"]?.stringValue ?? ""
            )
        }
        faces = (armour?["faces"]?.members ?? []).map { member in
            Face(id: member.key, area: member.value["area"]?.doubleValue ?? 0)
        }
        let thicknesses = (armour?["thickness_units"]?.items ?? []).compactMap { $0.intValue }
        thicknessRange = (thicknesses.min() ?? 1)...(thicknesses.max() ?? 4)

        arenas = (root["arenas"]?.members ?? []).map { member in
            let value = member.value
            return ArenaEntry(
                id: member.key,
                name: value["name"]?.stringValue ?? member.key,
                hazard: value["hazard"]?.stringValue ?? "",
                free: value["free"]?.boolValue ?? false
            )
        }
    }

    // MARK: - Pips

    /// Scale a catalogue number across the catalogue's own range onto 1 to 5.
    static func pip(_ value: Double, low: Double, high: Double) -> Int {
        guard high > low else { return 3 }
        let fraction = (value - low) / (high - low)
        return min(5, max(1, Int((fraction * 4).rounded()) + 1))
    }

    private static func scorePips<T>(
        _ items: inout [T],
        _ first: KeyPath<T, Double>, _ firstPips: WritableKeyPath<T, Int>,
        _ second: KeyPath<T, Double>, _ secondPips: WritableKeyPath<T, Int>,
        _ third: KeyPath<T, Double>, _ thirdPips: WritableKeyPath<T, Int>
    ) {
        guard !items.isEmpty else { return }
        let pairs = [(first, firstPips), (second, secondPips), (third, thirdPips)]
        for (source, destination) in pairs {
            let values = items.map { $0[keyPath: source] }
            guard let low = values.min(), let high = values.max() else { continue }
            for index in items.indices {
                items[index][keyPath: destination] = pip(items[index][keyPath: source], low: low, high: high)
            }
        }
    }

    /// Weapons need one inverted scale: a short setup time is a high pip.
    private static func scoreWeaponPips(_ weapons: inout [Weapon]) {
        guard !weapons.isEmpty else { return }
        let reaches = weapons.map(\.reach)
        let hits = weapons.map(\.hitValue)
        let setups = weapons.map(\.setupSeconds)
        let reachLow = reaches.min() ?? 0, reachHigh = reaches.max() ?? 1
        let hitLow = hits.min() ?? 0, hitHigh = hits.max() ?? 1
        let setupLow = setups.min() ?? 0, setupHigh = setups.max() ?? 1
        for index in weapons.indices {
            weapons[index].reachPips = pip(weapons[index].reach, low: reachLow, high: reachHigh)
            weapons[index].hitPips = pip(weapons[index].hitValue, low: hitLow, high: hitHigh)
            let slowness = pip(weapons[index].setupSeconds, low: setupLow, high: setupHigh)
            weapons[index].setupPips = 6 - slowness
        }
    }
}

extension String {
    /// "front" to "Front", leaving the rest of the string alone.
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
