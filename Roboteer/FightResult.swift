//
//  FightResult.swift
//  A Swift model of FightResult v1 (docs/bridge-spec.md). Every field is optional on the wire:
//  a missing key becomes a sensible default rather than a decoding failure, because a half
//  filled result is still worth showing and a crash on the results screen is not.
//

import Foundation

struct FightResult: Equatable {

    struct Outcome: Equatable {
        var type: String = "judges"
        var winner: String = ""
        var loser: String = ""
        var atSeconds: Double = 0

        /// Plain words for the four win conditions, per docs/stage3-spec.md section 8.
        var title: String {
            switch type {
            case "ko": return "Knockout"
            case "out_of_arena": return "Out of the arena"
            case "judges": return "Judges decision"
            case "component_kill": return "Core destroyed"
            case "timeout": return "Time ran out"
            default: return "Fight over"
            }
        }
    }

    struct JudgeScore: Equatable {
        var damage: Double = 0
        var aggression: Double = 0
        var control: Double = 0
        var total: Double { damage + aggression + control }
    }

    struct Armour: Equatable {
        var front: Double = 1
        var sides: Double = 1
        var rear: Double = 1
        var top: Double = 1
    }

    struct BotDamage: Equatable {
        var wheels: [Double] = []
        var weapon: Double = 1
        var armour = Armour()
        var drive: Double = 1
        var core: Double = 1

        /// A wheel still counts as on the bot while any condition is left in it.
        var wheelsIntact: Int { wheels.filter { $0 > 0 }.count }
        var wheelCount: Int { wheels.count }
    }

    // MARK: - v2 (wave P, additive; the wire schema stays 1)

    /// Weapon hits this bot landed on its opponents, and took from them.
    struct Hits: Equatable {
        var landed: Int = 0
        var taken: Int = 0
    }

    /// One part that went out during the fight. `state` is `destroyed` (its condition
    /// reached zero) or `disabled` (still on the machine but not answering: a jammed or
    /// cooked weapon, a burnt out drive).
    struct PartLost: Equatable {
        var part: String = ""
        var label: String = ""
        var state: String = "destroyed"

        var isDestroyed: Bool { state == "destroyed" }
        /// "Weapon destroyed", "Drive disabled": the words the report reads out.
        var sentence: String { "\(label) \(state)" }
    }

    var schema: Int = 1
    var outcome = Outcome()
    var durationSeconds: Double = 0
    var judges: [String: JudgeScore] = [:]
    var damage: [String: BotDamage] = [:]
    var scrap: [String: Int] = [:]
    /// v2. Weapon hits per bot, from the arena's tallies. Empty only for a result built
    /// by an arena older than wave P.
    var hits: [String: Hits] = [:]
    /// v2. Parts destroyed or disabled per bot, in report order.
    var partsLost: [String: [PartLost]] = [:]
    /// v2. Each bot's condition as the fight STARTED, so the report can show what this
    /// match cost rather than only the condition carried into the next one.
    var conditionStart: [String: BotDamage] = [:]
    /// v2. The scrap lines per bot. All zero when the fight carried no `rules.scrap`
    /// (a quick fight, an event, the test arena, the ladder); `scrap` is then still the
    /// legacy bolt total.
    var scrapBreakdown: [String: ScrapBreakdown] = [:]
    var replaySeed: Int?
    var replayTickHz: Int?
    var replayInputCount: Int = 0

    /// Ids in the order they should be shown: the order the configuration listed them, then any
    /// the arena mentioned that the configuration did not.
    func botIds(preferring order: [String]) -> [String] {
        var ids = order.filter { damage[$0] != nil || judges[$0] != nil || scrap[$0] != nil }
        let rest = Set(damage.keys).union(judges.keys).union(scrap.keys).subtracting(ids)
        ids.append(contentsOf: rest.sorted())
        return ids
    }

    // MARK: - Decoding

    /// Tolerant decode straight from `JSONSerialization`, which keeps every "missing key is fine"
    /// rule in one place and never throws on an unexpected shape.
    init?(json: String) {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        self.init(object: root)
    }

    init(object root: [String: Any]) {
        schema = Self.int(root["schema"]) ?? 1
        durationSeconds = Self.double(root["duration_s"]) ?? 0

        if let outcomeObject = root["outcome"] as? [String: Any] {
            outcome.type = outcomeObject["type"] as? String ?? "judges"
            outcome.winner = outcomeObject["winner"] as? String ?? ""
            outcome.loser = outcomeObject["loser"] as? String ?? ""
            outcome.atSeconds = Self.double(outcomeObject["at_s"]) ?? durationSeconds
        }
        if durationSeconds == 0 { durationSeconds = outcome.atSeconds }

        if let judgesObject = root["judges"] as? [String: Any] {
            for (id, value) in judgesObject {
                guard let entry = value as? [String: Any] else { continue }
                judges[id] = JudgeScore(
                    damage: Self.double(entry["damage"]) ?? 0,
                    aggression: Self.double(entry["aggression"]) ?? 0,
                    control: Self.double(entry["control"]) ?? 0
                )
            }
        }

        if let damageObject = root["damage"] as? [String: Any] {
            for (id, value) in damageObject {
                guard let entry = value as? [String: Any] else { continue }
                damage[id] = Self.botDamage(entry)
            }
        }

        if let scrapObject = root["scrap"] as? [String: Any] {
            for (id, value) in scrapObject {
                guard let amount = Self.double(value) else { continue }
                scrap[id] = Int(amount.rounded())
            }
        }

        // v2, all four tolerated as missing: a pre wave P arena sends none of them.
        if let hitsObject = root["hits"] as? [String: Any] {
            for (id, value) in hitsObject {
                guard let entry = value as? [String: Any] else { continue }
                hits[id] = Hits(
                    landed: Self.int(entry["landed"]) ?? 0,
                    taken: Self.int(entry["taken"]) ?? 0
                )
            }
        }

        if let lostObject = root["parts_lost"] as? [String: Any] {
            for (id, value) in lostObject {
                guard let rows = value as? [Any] else { continue }
                partsLost[id] = rows.compactMap { row in
                    guard let entry = row as? [String: Any] else { return nil }
                    let part = entry["part"] as? String ?? ""
                    let label = entry["label"] as? String ?? part
                    guard !part.isEmpty || !label.isEmpty else { return nil }
                    return PartLost(
                        part: part,
                        label: label,
                        state: entry["state"] as? String ?? "destroyed"
                    )
                }
            }
        }

        if let startObject = root["condition_start"] as? [String: Any] {
            for (id, value) in startObject {
                guard let entry = value as? [String: Any] else { continue }
                conditionStart[id] = Self.botDamage(entry)
            }
        }

        if let breakdownObject = root["scrap_breakdown"] as? [String: Any] {
            for (id, value) in breakdownObject {
                guard let entry = value as? [String: Any] else { continue }
                // `total` is computed from the four lines on the Swift side, so it is read
                // for nothing here: the arena's total is the same sum by construction.
                scrapBreakdown[id] = ScrapBreakdown(
                    base: Self.int(entry["base"]) ?? 0,
                    damage: Self.int(entry["damage"]) ?? 0,
                    survivor: Self.int(entry["survivor"]) ?? 0,
                    flawless: Self.int(entry["flawless"]) ?? 0
                )
            }
        }

        if let replay = root["replay"] as? [String: Any] {
            replaySeed = Self.int(replay["seed"])
            replayTickHz = Self.int(replay["tick_hz"])
            replayInputCount = (replay["inputs"] as? [Any])?.count ?? 0
        }
    }

    /// One condition dictionary (the FightConfig `damage` shape) as a `BotDamage`. Shared by
    /// `damage` and v2's `condition_start` so the two can never drift apart.
    private static func botDamage(_ entry: [String: Any]) -> BotDamage {
        var bot = BotDamage()
        if let wheels = entry["wheels"] as? [Any] {
            bot.wheels = wheels.compactMap { double($0) }
        }
        bot.weapon = double(entry["weapon"]) ?? 1
        bot.drive = double(entry["drive"]) ?? 1
        bot.core = double(entry["core"]) ?? 1
        if let armour = entry["armour"] as? [String: Any] {
            bot.armour = Armour(
                front: double(armour["front"]) ?? 1,
                sides: double(armour["sides"]) ?? 1,
                rear: double(armour["rear"]) ?? 1,
                top: double(armour["top"]) ?? 1
            )
        }
        return bot
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }
}
