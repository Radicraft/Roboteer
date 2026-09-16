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
    /// The card the season screen printed. The report is the long version of it, so the house bot,
    /// the arena and the money come from the same value rather than being worked out twice.
    let next: NextFight?

    @Binding var chosenID: PersistentIdentifier?
    var onFight: () -> Void
    var onBack: () -> Void

    private var catalogue: Catalogue { Catalogue.shared }

    private var chosen: BotBuild? {
        builds.first { $0.persistentModelID == chosenID } ?? builds.first { !$0.isWrittenOff }
    }

    private static let gutter: CGFloat = 26

    var body: some View {
        ZStack {
            StageBackdrop(host: host, still: .withBot, dim: 0.24)

            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 10) {
                    header
                    HStack(spacing: 0) {
                        // Their machine is orbiting here. The point of the screen is to look at it,
                        // so the report stands beside it rather than on top of it, and a drag over
                        // it turns it: this is where you check their clearance and weapon height.
                        StageOrbitPad(host: host)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        VStack(alignment: .leading, spacing: 8) {
                            opponentPanel
                            stable
                        }
                        .frame(width: StageLayout.columnWidth(proxy.size.width - 2 * Self.gutter))
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .padding(.horizontal, Self.gutter)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            showOpponentOnStage()
            registerFocus()
        }
        .onChange(of: chosen?.persistentModelID) { _, _ in registerFocus() }
    }

    /// The stage orbits their machine while this screen is up, framed at 28 % across so the report
    /// beside it never covers it.
    private func showOpponentOnStage() {
        host.sendWorkshopConfig(
            opponent.spec.toBotConfig(id: "scout-1", controller: "dummy"),
            mode: "scout",
            frame: StageLayout.botFrame
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
            Text("\(tier.title.uppercased()), \(CareerBracket.roundTitle(round, of: CareerBracket.rounds).uppercased())")
                .font(Stage.label(11))
                .foregroundStyle(Stage.textFaint)
            Spacer(minLength: 8)
            ScrapBadge(amount: scrap)
        }
    }

    // MARK: - The opponent

    private var opponentPanel: some View {
        GlassPanel(padding: 12) {
            ScrollView {
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

                // Brief v4 section 3: the scouting report names the house bot on duty and says
                // what it does, and section 6 wants the money on screen before the fight.
                if let next {
                    StageStat(label: "Arena", value: next.arenaName)
                    StageStat(label: "House bot", value: next.houseBotName)
                    Text(next.houseBotLine)
                        .font(Stage.body(10))
                        .foregroundStyle(Stage.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                    StageStat(label: "Entry paid", value: "\(next.entryFee)")
                    StageStat(label: next.isFinal ? "The final pays" : "A win pays", value: "\(next.purse)", tint: Stage.gold)
                    if next.repairsDue > 0 {
                        StageStat(label: "Repairs owing", value: "\(next.repairsDue)", tint: Stage.danger)
                    }
                    Divider().overlay(Stage.edge)
                }

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
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    /// Which of yours you are sending. One row of cards under the report rather than a second
    /// column, because the column is the report and the left of the screen is their machine.
    private var stable: some View {
        VStack(alignment: .leading, spacing: 6) {
            StageHeading("Choose your bot")

            if builds.allSatisfy(\.isWrittenOff) {
                Text("Every machine in the garage is written off. Build a new one.")
                    .font(Stage.body(11))
                    .foregroundStyle(Stage.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(builds.filter { !$0.isWrittenOff }) { build in
                            botRow(build)
                        }
                    }
                    .padding(.bottom, 2)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            if let chosen, !chosen.damageJSON.isEmpty {
                Text("\(chosen.name) is carrying damage. It fights as it stands.")
                    .font(Stage.body(10))
                    .foregroundStyle(Stage.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            StageButton("Fight", kind: .primary, enabled: chosen?.isValid ?? false, focusID: "fight", action: onFight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
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
            HStack(alignment: .center, spacing: 8) {
                LiverySwatch(hex: build.liveryHex, size: 18, selected: isChosen)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(build.name.uppercased())
                            .font(Stage.display(14))
                            .kerning(0.6)
                            .foregroundStyle(Stage.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
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
            .frame(width: 168, alignment: .leading)
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
