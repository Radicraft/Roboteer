//
//  ResultSheet.swift
//  What happened, in plain words: the outcome, the winner, the damage, the scrap and the scores.
//  Reads FightResult v1 (docs/bridge-spec.md). Restyled for Stage 4: dark glass over the stage,
//  bold condensed capitals, gold on the scrap and the winner mark and nowhere else.
//
//  A quick fight is an exhibition: nothing is written into the machine's record and no damage is
//  carried home (bug 10 of docs/aaa/frontend-meta.md). The record is the career's.
//

import SwiftUI
import SwiftData

struct ResultSheet: View {

    @Bindable var host: ArenaHost
    let result: FightResult?
    /// The player's machine. Kept for the callers; an exhibition writes nothing into it.
    var player: BotBuild?
    var onBackToGarage: () -> Void

    var body: some View {
        ZStack {
            Stage.ground.ignoresSafeArea()
            StageStill(kind: .empty)
                .opacity(0.35)
                .ignoresSafeArea()
            Stage.ink.opacity(0.62).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        if let result {
                            if let card = judgesCard(result) {
                                // Wave B judges: a decision on the cards shows why, FIRST
                                // (integration 2026-09-28: under the two machine panels it
                                // started below the fold of a 402 pt phone, so the sheet
                                // answered "why did I lose" only after a scroll).
                                GlassPanel(padding: 14) {
                                    JudgesCardView(card: card, wide: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                botColumns(result)
                            } else {
                                botColumns(result)
                                judges(result)
                            }
                        } else {
                            GlassPanel {
                                Text("The arena finished the fight but sent nothing this build could read.")
                                    .font(Stage.label(14))
                                    .foregroundStyle(Stage.typeDim)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)

                // Pinned, not scrolled to. A player who has just lost has to be able to leave
                // without reading the judges' card first.
                backButton
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Header

    /// Won, lost or drawn, decided the same way the career's match report decides it: a result
    /// with no winner is a draw (bug 8 of docs/aaa/frontend-meta.md; it used to read LOST).
    private var outcome: MatchReport.Result? {
        guard let result else { return nil }
        return ProgressionEngine.resultKind(winner: result.outcome.winner, playerID: FightConfigFixture.playerID)
    }

    /// The display banner (design system section 5): WON in `win`, LOST in `danger`, as a lower
    /// third that slams in from the left it belongs to.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            LowerThird(bar: outcome.map(PostMatch.bar) ?? Stage.lineDim, entersFrom: .leading) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(outcome.map(PostMatch.word) ?? "OVER")
                        .font(Stage.display(44))
                        .kerning(Stage.Tracking.display(44))
                        .foregroundStyle(outcome.map(PostMatch.tint) ?? Stage.type)
                    Text(result?.outcome.title.uppercased() ?? "FIGHT OVER")
                        .font(Stage.display(22))
                        .kerning(Stage.Tracking.display(22))
                        .foregroundStyle(Stage.type)
                        .lineLimit(1)
                        .minimumScaleFactor(BroadcastType.floorScale(.display, size: 22, wanted: 0.7))
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if let result {
                Text("\(winnerLine(result)) Time: \(duration(result.durationSeconds)).")
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.typeDim)
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
                            .font(Stage.label(11, weight: .bold))
                            .kerning(1.2)
                            .foregroundStyle(Stage.ink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Stage.win, in: PlateRect())
                    }
                    Spacer(minLength: 0)
                }

                // The scrap counts up over 0.4 s (design system section 3).
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CountingNumber(value: result.scrap[id] ?? 0, font: Stage.numerals(24), tint: Stage.scrap)
                        .figureLine(24)
                    Text("SCRAP")
                        .font(Stage.label(11))
                        .kerning(Stage.Tracking.label(11))
                        .foregroundStyle(Stage.scrap.opacity(0.8))
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
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.textFaint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        StageStat(label: label, value: value, tint: Stage.typeDim)
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

    /// The card with its words, for a judges' decision. Nil for any other finish, where the old
    /// table of the scores at that moment is still what is shown.
    private func judgesCard(_ result: FightResult) -> JudgesCard? {
        guard result.outcome.type == "judges" else { return nil }
        let me = FightConfigFixture.playerID
        guard let them = result.judges.keys.sorted().first(where: { $0 != me }) else { return nil }
        return JudgesCard.make(result: result, myID: me, myName: host.name(for: me),
                               theirName: host.name(for: them))
    }

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
            .font(heading ? Stage.label(11, weight: .bold) : Stage.figure(text, size: 13))
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
    }
}
