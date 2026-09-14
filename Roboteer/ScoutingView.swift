//
//  ScoutingView.swift
//  The scouting report: who you are about to fight, what they are made of, what they have to say
//  about you, and which of your machines you are going to send.
//
//  The stage behind the panels is showing THEIR bot: this screen sends `workshop_config` with
//  `"mode": "scout"` so the arena orbits the opponent rather than standing the player's own
//  machine on the turntable (brief section 4, docs/stage5-spec.md section 2).
//

import SwiftUI
import SwiftData

struct ScoutingView: View {

    @Bindable var host: ArenaHost

    let opponent: CareerEntrant
    let tier: CareerTier
    let round: Int
    let builds: [BotBuild]
    let record: RivalRecord?
    let scrap: Int

    @Binding var chosenID: PersistentIdentifier?
    var onFight: () -> Void
    var onBack: () -> Void

    private var catalogue: Catalogue { Catalogue.shared }

    private var chosen: BotBuild? {
        builds.first { $0.persistentModelID == chosenID } ?? builds.first { !$0.isWrittenOff }
    }

    var body: some View {
        ZStack {
            StageBackdrop(host: host, still: .withBot, dim: 0.34)

            VStack(alignment: .leading, spacing: 10) {
                header
                HStack(alignment: .top, spacing: 16) {
                    opponentPanel
                    Spacer(minLength: 0)
                    stable
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            showOpponentOnStage()
            registerFocus()
        }
        .onChange(of: chosen?.persistentModelID) { _, _ in registerFocus() }
    }

    /// The stage orbits their machine while this screen is up.
    private func showOpponentOnStage() {
        host.sendWorkshopConfig(
            opponent.spec.toBotConfig(id: "scout-1", controller: "dummy"),
            mode: "scout"
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            StageButton("Back", kind: .quiet, action: onBack)
                .frame(width: 96)
            Text("SCOUTING REPORT")
                .font(Stage.display(22))
                .kerning(1.6)
                .foregroundStyle(Stage.text)
            Text("\(tier.title.uppercased()), \(CareerBracket.roundName(round, of: CareerBracket.rounds).uppercased())")
                .font(Stage.label(11))
                .foregroundStyle(Stage.textFaint)
            Spacer(minLength: 8)
            ScrapBadge(amount: scrap)
        }
    }

    // MARK: - The opponent

    private var opponentPanel: some View {
        GlassPanel(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    LiverySwatch(hex: opponent.liveryHex, size: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(opponent.name.uppercased())
                            .font(Stage.display(21))
                            .kerning(1)
                            .foregroundStyle(Stage.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(opponent.roboteer)
                            .font(Stage.label(11))
                            .foregroundStyle(Stage.textDim)
                    }
                    Spacer(minLength: 0)
                    Text(BuildRules.kilograms(BuildRules.totalWeight(opponent.spec)))
                        .font(Stage.numerals(15))
                        .foregroundStyle(Stage.textDim)
                }

                Text(opponent.spec.partsLine)
                    .font(Stage.label(12))
                    .foregroundStyle(Stage.text)
                Text(opponent.spec.armourLine)
                    .font(Stage.body(11))
                    .foregroundStyle(Stage.textFaint)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let weapon = catalogue.weapon(opponent.spec.weapon) {
                            StatPips(label: "Reach", filled: weapon.reachPips, width: 46)
                            StatPips(label: "Hit", filled: weapon.hitPips, width: 46)
                            StatPips(label: "Setup", filled: weapon.setupPips, width: 46)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        if let drive = catalogue.drive(opponent.spec.drive) {
                            StatPips(label: "Speed", filled: drive.speedPips, width: 46)
                            StatPips(label: "Turn", filled: drive.turnPips, width: 46)
                            StatPips(label: "Push", filled: drive.pushPips, width: 46)
                        }
                    }
                }

                Divider().overlay(Stage.edge)

                Text(grudgeLine)
                    .font(Stage.body(12))
                    .italic()
                    .foregroundStyle(Stage.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(historyLine)
                    .font(Stage.body(10))
                    .foregroundStyle(Stage.textFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 330)
    }

    private var grudgeLine: String {
        if let record, !record.grudgeLines.isEmpty {
            return CareerEngine.grudgeLine(
                lines: record.grudgeLines,
                wins: record.winsVsPlayer,
                losses: record.lossesVsPlayer,
                theyWonLast: record.lastResultWasTheirs,
                playerName: record.roboteer,
                botName: chosen?.name ?? "your machine"
            )
        }
        if let rival = CareerCatalogue.shared.rival(opponent.rivalID), !rival.personality.isEmpty {
            return rival.personality
        }
        return "Nobody knows much about this one. That cuts both ways."
    }

    private var historyLine: String {
        guard let record, record.hasMet else { return "You have never met." }
        let wins = record.lossesVsPlayer
        let losses = record.winsVsPlayer
        var line = "You have beaten \(record.name) \(wins) \(wins == 1 ? "time" : "times") and lost \(losses)."
        if !record.lastMetTier.isEmpty, record.lastMetRound >= 0 {
            let tierName = CareerTier.named(record.lastMetTier).title
            line += " Last met in the \(tierName) \(CareerBracket.roundName(record.lastMetRound, of: CareerBracket.rounds))."
        }
        return line
    }

    // MARK: - Your stable

    private var stable: some View {
        VStack(alignment: .leading, spacing: 8) {
            StageHeading("Choose your bot")

            GlassPanel(padding: 8) {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(builds.filter { !$0.isWrittenOff }) { build in
                            botRow(build)
                        }
                        if builds.allSatisfy(\.isWrittenOff) {
                            Text("Every machine in the garage is written off. Build a new one.")
                                .font(Stage.body(11))
                                .foregroundStyle(Stage.danger)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            if let chosen, !chosen.damageJSON.isEmpty {
                Text("\(chosen.name) is carrying damage. It fights as it stands.")
                    .font(Stage.body(10))
                    .foregroundStyle(Stage.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            StageButton("Fight", kind: .primary, enabled: chosen?.isValid ?? false, focusID: "fight", action: onFight)
        }
        .frame(width: 250)
    }

    private func registerFocus() {
        PadFocus.shared.set(
            [PadItem("fight", enabled: chosen?.isValid ?? false) { onFight() }],
            back: { onBack() }
        )
    }

    private func botRow(_ build: BotBuild) -> some View {
        let isChosen = build.persistentModelID == (chosen?.persistentModelID)
        return Button {
            chosenID = build.persistentModelID
        } label: {
            HStack(alignment: .top, spacing: 8) {
                LiverySwatch(hex: build.liveryHex, size: 18, selected: isChosen)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(build.name.uppercased())
                            .font(Stage.display(14))
                            .kerning(0.6)
                            .foregroundStyle(Stage.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 2)
                        Text(BuildRules.kilograms(build.totalWeight))
                            .font(Stage.numerals(12))
                            .foregroundStyle(build.isValid ? Stage.textDim : Stage.danger)
                    }
                    Text(build.partsLine)
                        .font(Stage.body(10))
                        .foregroundStyle(Stage.textFaint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isChosen ? 0.12 : 0.03))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isChosen ? Stage.edgeBright : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scrap

/// The scrap balance, in the one colour gold is allowed to be used for.
struct ScrapBadge: View {
    let amount: Int
    var size: CGFloat = 18

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(amount)")
                .font(Stage.numerals(size))
                .foregroundStyle(Stage.gold)
            Text("SCRAP")
                .font(Stage.label(9, weight: .bold))
                .kerning(1.2)
                .foregroundStyle(Stage.gold.opacity(0.8))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(amount) scrap")
    }
}
