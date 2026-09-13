//
//  ResultSheet.swift
//  What happened, in plain words: the outcome, the winner, the damage, the scrap and the scores.
//  Reads FightResult v1 (docs/bridge-spec.md). Restyled for Stage 4: dark glass over the stage,
//  bold condensed capitals, gold on the scrap and the winner mark and nowhere else.
//
//  It is also where a fight is written into the machine's record and its damage is carried home.
//

import SwiftUI
import SwiftData

struct ResultSheet: View {

    @Bindable var host: ArenaHost
    let result: FightResult?
    /// The player's machine, so the fight can be written into its record.
    var player: BotBuild?
    var onBackToGarage: () -> Void

    @Environment(\.modelContext) private var context
    @State private var didRecord = false

    var body: some View {
        ZStack {
            Stage.ground.ignoresSafeArea()
            StageStill(kind: .empty)
                .opacity(0.35)
                .ignoresSafeArea()
            Color.black.opacity(0.45).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let result {
                        botColumns(result)
                        judges(result)
                    } else {
                        GlassPanel {
                            Text("The arena finished the fight but sent nothing this build could read.")
                                .font(Stage.label(14))
                                .foregroundStyle(Stage.textDim)
                        }
                    }
                    backButton
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear { record() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result?.outcome.title.uppercased() ?? "FIGHT OVER")
                .font(Stage.display(38, weight: .black))
                .kerning(1.6)
                .foregroundStyle(Stage.text)

            Rectangle()
                .fill(Stage.text.opacity(0.8))
                .frame(width: 66, height: 3)

            if let result {
                Text(winnerLine(result))
                    .font(Stage.label(16))
                    .foregroundStyle(Stage.textDim)

                Text("Time: \(duration(result.durationSeconds)).")
                    .font(Stage.body(12))
                    .foregroundStyle(Stage.textFaint)
            }
        }
    }

    private func winnerLine(_ result: FightResult) -> String {
        let winner = result.outcome.winner
        guard !winner.isEmpty else { return "No winner was recorded." }
        return "\(host.name(for: winner)) wins."
    }

    private func duration(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        let minutes = whole / 60
        let rest = whole % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, rest)
        }
        return String(format: "%.1f seconds", seconds)
    }

    // MARK: - Per bot

    private func botColumns(_ result: FightResult) -> some View {
        let ids = result.botIds(preferring: host.botOrder.isEmpty ? FightConfigFixture.stage3BotOrder : host.botOrder)
        return HStack(alignment: .top, spacing: 16) {
            ForEach(ids, id: \.self) { id in
                botPanel(id: id, result: result)
            }
        }
    }

    private func botPanel(id: String, result: FightResult) -> some View {
        let damage = result.damage[id]
        return GlassPanel(padding: 14) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(host.name(for: id).uppercased())
                        .font(Stage.display(19))
                        .kerning(1)
                        .foregroundStyle(Stage.text)
                    if id == result.outcome.winner {
                        Text("WINNER")
                            .font(Stage.label(9, weight: .bold))
                            .kerning(1.2)
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Stage.gold, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                    Spacer(minLength: 0)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(result.scrap[id] ?? 0)")
                        .font(Stage.numerals(22))
                        .foregroundStyle(Stage.gold)
                    Text("SCRAP")
                        .font(Stage.label(10, weight: .bold))
                        .kerning(1.2)
                        .foregroundStyle(Stage.gold.opacity(0.8))
                }

                if let damage {
                    line("Wheels", "\(damage.wheelsIntact) of \(damage.wheelCount) still on")
                    line("Weapon", condition(damage.weapon))
                    line("Drive", condition(damage.drive))
                    line("Core", condition(damage.core))
                    StageHeading("Armour")
                        .padding(.top, 3)
                    line("Front", condition(damage.armour.front))
                    line("Sides", condition(damage.armour.sides))
                    line("Rear", condition(damage.armour.rear))
                    line("Top", condition(damage.armour.top))
                } else {
                    Text("No damage was reported for this bot.")
                        .font(Stage.body(11))
                        .foregroundStyle(Stage.textFaint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label.uppercased())
                .font(Stage.label(10, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(Stage.textFaint)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(Stage.body(12))
                .foregroundStyle(Stage.textDim)
        }
    }

    /// Condition in plain words, with the number after it so nothing is lost.
    private func condition(_ value: Double) -> String {
        let percent = Int((max(0, min(1, value)) * 100).rounded())
        let word: String
        switch value {
        case ..<0.001: word = "gone"
        case ..<0.35: word = "wrecked"
        case ..<0.7: word = "battered"
        case ..<0.999: word = "scuffed"
        default: word = "pristine"
        }
        return "\(word) (\(percent)%)"
    }

    // MARK: - Judges

    private func judges(_ result: FightResult) -> some View {
        let ids = result.botIds(preferring: host.botOrder.isEmpty ? FightConfigFixture.stage3BotOrder : host.botOrder)
        return GlassPanel(padding: 14) {
            VStack(alignment: .leading, spacing: 7) {
                StageHeading("Judges scores")

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                    GridRow {
                        scoreCell("", heading: true)
                        scoreCell("DAMAGE", heading: true)
                        scoreCell("AGGRESSION", heading: true)
                        scoreCell("CONTROL", heading: true)
                        scoreCell("TOTAL", heading: true)
                    }
                    ForEach(ids, id: \.self) { id in
                        let score = result.judges[id] ?? FightResult.JudgeScore()
                        GridRow {
                            scoreCell(host.name(for: id), heading: false)
                            scoreCell(number(score.damage), heading: false)
                            scoreCell(number(score.aggression), heading: false)
                            scoreCell(number(score.control), heading: false)
                            scoreCell(number(score.total), heading: false)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func scoreCell(_ text: String, heading: Bool) -> some View {
        Text(heading ? text : text.uppercased())
            .font(heading ? Stage.label(10, weight: .bold) : Stage.numerals(13))
            .kerning(heading ? 1 : 0)
            .foregroundStyle(heading ? Stage.textFaint : Stage.text)
    }

    private func number(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    // MARK: - Back

    private var backButton: some View {
        StageButton("Back to garage", kind: .primary, action: onBackToGarage)
            .frame(maxWidth: 280)
            .padding(.top, 2)
    }

    // MARK: - The record

    /// One fight, written into the machine once: the tally, who killed it, and the damage it is
    /// carrying home so the next fight starts from where this one ended.
    private func record() {
        guard !didRecord, let result, let player else { return }
        didRecord = true

        let id = FightConfigFixture.playerID
        player.fights += 1
        if result.outcome.winner == id {
            player.wins += 1
            if result.outcome.type == "ko" || result.outcome.type == "component_kill" {
                player.kos += 1
            }
        }
        if result.outcome.loser == id,
           result.outcome.type == "ko" || result.outcome.type == "component_kill" {
            player.killedBy = host.name(for: result.outcome.winner)
        }

        if let damage = result.damage[id] {
            player.damageJSON = JSONText.string(from: [
                "wheels": damage.wheels,
                "weapon": damage.weapon,
                "armour": [
                    "front": damage.armour.front,
                    "sides": damage.armour.sides,
                    "rear": damage.armour.rear,
                    "top": damage.armour.top
                ],
                "drive": damage.drive,
                "core": damage.core
            ])
        }
        try? context.save()
    }
}
