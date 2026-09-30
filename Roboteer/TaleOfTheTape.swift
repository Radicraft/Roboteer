//
//  TaleOfTheTape.swift
//  The walk-outs' cards (wave D, docs/wave-d-walkout-notes.md).
//
//  Before a career fight (and, shorter, a quick fight) each machine rolls out of its venue gate
//  with a card on screen: its name, who built it, mass, drive, weapon, a few whole-machine
//  numbers, the head to head, and a STRENGTH and a WEAKNESS line. The player writes their own
//  two lines in the builder (`TapeLinesSheet`); rivals and house bots have theirs written in
//  `Shared/parts.json`; anything else gets lines made from its build.
//
//  This file turns all of that into `fight_config.tape` (docs/bridge-spec.md). It is injected at
//  send time like the intro (`ArenaHost.tapeNextFight`) and never stored in
//  `lastFightConfigJSON`, so replays are unaffected. The arena draws what it is sent and makes up
//  anything left out, with the same default-line rules as `defaultLines` here
//  (`Arena/fight/tape_cards.gd`).
//

import Foundation
import SwiftData

enum TaleOfTheTape {

    /// A typed line is cut to this many characters. The arena caps at the same number.
    static let lineLimit = 60

    enum Style: String {
        /// A career match: the long walk-outs, and the house bot's shot on a first visit.
        case career
        /// A quick fight or a ladder ghost: shorter walk-outs.
        case quick
    }

    // MARK: - The player's own lines

    /// Trimmed, one line, runs of spaces collapsed, at most `lineLimit` characters (cut at a word
    /// when there is one in the last 40 %). Nothing is policed; empty means "use the default".
    static func clean(_ text: String?) -> String {
        guard let text else { return "" }
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        guard flat.count > lineLimit else { return flat }
        var cut = String(flat.prefix(lineLimit))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > Int(Double(lineLimit) * 0.6) {
            cut = String(cut[..<space])
        }
        return cut.trimmingCharacters(in: .whitespaces)
    }

    /// The lines a machine gets when nobody has written any: the weapon's weight as the
    /// strength, and the most obvious hole in the build as the weakness. The arena makes the
    /// same two from a bare configuration (`TapeCards.default_lines`), so keep them in step.
    static func defaultLines(for spec: BuildSpec) -> (strength: String, weakness: String) {
        let catalogue = Catalogue.shared
        var strength = "Nothing to lose."
        if let weapon = catalogue.weapon(spec.weapon), weapon.weight > 0 {
            strength = "\(BuildRules.kilograms(weapon.weight)) of \(weapon.name.lowercased())."
        }
        let rear = spec.armour["rear"]
        let top = spec.armour["top"]
        let invertible = catalogue.chassis(spec.chassis)?.invertible ?? false
        let weakness: String
        if let rear, ["polycarbonate", "hdpe"].contains(rear.material), rear.thickness <= 1 {
            weakness = "The back end is mostly hope."
        } else if spec.drive == "2wd" {
            weakness = "Two wheels, both load bearing."
        } else if !spec.utilities.contains("srimech"), !invertible {
            weakness = "Upside down, it is an ornament."
        } else if let top, top.thickness <= 1 {
            weakness = "Thin on top, and sensitive about it."
        } else {
            weakness = "It knows it."
        }
        return (strength, weakness)
    }

    /// The player's lines for this machine: what they wrote, or the default for each one left
    /// empty.
    static func lines(for build: BotBuild) -> (strength: String, weakness: String) {
        let made = defaultLines(for: build.spec)
        let strength = clean(build.strengthLine)
        let weakness = clean(build.weaknessLine)
        return (strength.isEmpty ? made.strength : strength, weakness.isEmpty ? made.weakness : weakness)
    }

    // MARK: - Written lines from the catalogue

    /// A rival's or a house bot's written `strength` and `weakness` in `Shared/parts.json`.
    static func writtenLines(section: String, id: String) -> (strength: String, weakness: String)? {
        guard !id.isEmpty, let entry = catalogueRoot?[section]?[id],
              let strength = entry["strength"]?.stringValue, let weakness = entry["weakness"]?.stringValue,
              !strength.isEmpty, !weakness.isEmpty else { return nil }
        return (strength, weakness)
    }

    private static let catalogueRoot: JSONValue? = {
        guard let url = Bundle.main.url(forResource: "parts", withExtension: "json"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return JSONValue.parse(text)
    }()

    // MARK: - One card

    /// A card as the bridge carries it. Every value is a display string.
    static func card(
        side: String,
        spec: BuildSpec,
        name: String,
        roboteer: String,
        record: String,
        lines: (strength: String, weakness: String)
    ) -> [String: Any] {
        let catalogue = Catalogue.shared
        var stats: [[String: Any]] = []
        if let drive = catalogue.drive(spec.drive) {
            stats.append(["label": "SPEED", "value": "\(drive.speedPips)/5"])
        }
        if let weapon = catalogue.weapon(spec.weapon) {
            stats.append(["label": "HIT", "value": "\(weapon.hitPips)/5"])
        }
        stats.append(["label": "ARMOUR", "value": BuildRules.kilograms(BuildRules.armourWeight(spec))])
        return [
            "side": side,
            "label": side == "player" ? "YOUR MACHINE" : (side == "house" ? "HOUSE BOT" : "OPPONENT"),
            "name": name,
            "roboteer": roboteer,
            "mass": BuildRules.kilograms(BuildRules.totalWeight(spec)),
            "drive": catalogue.drive(spec.drive)?.name ?? spec.drive,
            "weapon": catalogue.weapon(spec.weapon)?.name ?? spec.weapon,
            "stats": stats,
            "record": record,
            "strength": clean(lines.strength),
            "weakness": clean(lines.weakness)
        ]
    }

    /// The house bot on duty. Its roboteer line is its signature move.
    static func houseCard(id: String) -> [String: Any]? {
        guard !id.isEmpty, let boss = CareerCatalogue.shared.boss(id) else { return nil }
        let lines = writtenLines(section: "bosses", id: id) ?? defaultLines(for: boss.spec)
        return card(side: "house", spec: boss.spec, name: boss.name, roboteer: boss.signature,
                    record: "", lines: lines)
    }

    /// An opponent: a rival's written lines, anyone else's made from the build.
    static func opponentCard(_ entrant: CareerEntrant, record: String) -> [String: Any] {
        let lines = writtenLines(section: "rivals", id: entrant.rivalID) ?? defaultLines(for: entrant.spec)
        return card(side: "opponent", spec: entrant.spec, name: entrant.name, roboteer: entrant.roboteer,
                    record: record, lines: lines)
    }

    /// The player's machine. With no saved build to hand (a fixture), the configuration's own
    /// name and the default lines.
    static func playerCard(build: BotBuild?, fallbackName: String, record: String) -> [String: Any] {
        guard let build else {
            let spec = BuildSpec.defaultWedge
            return card(side: "player", spec: spec, name: fallbackName, roboteer: "", record: record,
                        lines: defaultLines(for: spec))
        }
        return card(side: "player", spec: build.spec, name: build.name, roboteer: "", record: record,
                    lines: lines(for: build))
    }

    /// `fight_config.tape`.
    static func tape(style: Style, cards: [[String: Any]]) -> [String: Any] {
        ["style": style.rawValue, "cards": cards]
    }

    // MARK: - The head to head

    /// "First meeting", or "Won 2, lost 1 against Clatterbox" from `winner`'s side. `wins` and
    /// `losses` are that side's.
    static func record(wins: Int, losses: Int, against name: String) -> String {
        guard wins + losses > 0 else { return "First meeting" }
        return "Won \(wins), lost \(losses) against \(name)"
    }

    /// The career head to head with an opponent: a rival's record, or the fight log by name.
    static func careerRecord(opponent: CareerEntrant, in context: ModelContext) -> (wins: Int, losses: Int) {
        if let rival = CareerStore.record(for: opponent.rivalID, in: context) {
            return (rival.lossesVsPlayer, rival.winsVsPlayer)
        }
        let name = opponent.name
        let logs = (try? context.fetch(FetchDescriptor<FightLog>(predicate: #Predicate { $0.opponentName == name }))) ?? []
        let career = logs.filter { $0.source == FightLog.Source.career }
        let wins = career.filter { $0.didWin }.count
        return (wins, career.count - wins)
    }

    /// The saved machine a configuration was built from: by name, the selected one first.
    static func build(named name: String, in context: ModelContext) -> BotBuild? {
        let all = (try? context.fetch(FetchDescriptor<BotBuild>())) ?? []
        return all.first { $0.name == name && $0.isSelected } ?? all.first { $0.name == name }
    }

    // MARK: - Whole fights

    /// A career match (or a ladder ghost, `next == nil`).
    static func forCareer(
        playerConfig: [String: Any],
        opponentConfig: [String: Any],
        next: NextMatch?,
        context: ModelContext
    ) -> [String: Any] {
        let playerName = playerConfig["name"] as? String ?? "Your machine"
        let build = build(named: playerName, in: context)
        var cards: [[String: Any]] = []
        if let next {
            let (wins, losses) = careerRecord(opponent: next.opponent, in: context)
            cards.append(opponentCard(next.opponent, record: record(wins: losses, losses: wins, against: playerName)))
            cards.append(playerCard(build: build, fallbackName: playerName,
                                    record: record(wins: wins, losses: losses, against: next.opponent.name)))
            if next.hasHouseBot, let house = houseCard(id: next.houseBotID) {
                cards.append(house)
            }
            return tape(style: .career, cards: cards)
        }
        // The ladder's ghost: only its name is known here; the arena fills the rest from the
        // configuration.
        cards.append(["side": "opponent", "record": "Ladder"])
        cards.append(playerCard(build: build, fallbackName: playerName, record: "Ladder"))
        _ = opponentConfig
        return tape(style: .quick, cards: cards)
    }

    /// A quick fight: an exhibition, so no head to head.
    static func forQuickFight(
        build: BotBuild?,
        playerName: String,
        opponent: CareerEntrant?,
        houseBotID: String?
    ) -> [String: Any] {
        var cards: [[String: Any]] = []
        if let opponent {
            cards.append(opponentCard(opponent, record: "Exhibition"))
        }
        cards.append(playerCard(build: build, fallbackName: playerName, record: "Exhibition"))
        if let houseBotID, let house = houseCard(id: houseBotID) {
            cards.append(house)
        }
        return tape(style: .quick, cards: cards)
    }
}
