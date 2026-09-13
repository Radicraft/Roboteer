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

    var schema: Int = 1
    var outcome = Outcome()
    var durationSeconds: Double = 0
    var judges: [String: JudgeScore] = [:]
    var damage: [String: BotDamage] = [:]
    var scrap: [String: Int] = [:]
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
                var bot = BotDamage()
                if let wheels = entry["wheels"] as? [Any] {
                    bot.wheels = wheels.compactMap { Self.double($0) }
                }
                bot.weapon = Self.double(entry["weapon"]) ?? 1
                bot.drive = Self.double(entry["drive"]) ?? 1
                bot.core = Self.double(entry["core"]) ?? 1
                if let armour = entry["armour"] as? [String: Any] {
                    bot.armour = Armour(
                        front: Self.double(armour["front"]) ?? 1,
                        sides: Self.double(armour["sides"]) ?? 1,
                        rear: Self.double(armour["rear"]) ?? 1,
                        top: Self.double(armour["top"]) ?? 1
                    )
                }
                damage[id] = bot
            }
        }

        if let scrapObject = root["scrap"] as? [String: Any] {
            for (id, value) in scrapObject {
                guard let amount = Self.double(value) else { continue }
                scrap[id] = Int(amount.rounded())
            }
        }

        if let replay = root["replay"] as? [String: Any] {
            replaySeed = Self.int(replay["seed"])
            replayTickHz = Self.int(replay["tick_hz"])
            replayInputCount = (replay["inputs"] as? [Any])?.count ?? 0
        }
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
