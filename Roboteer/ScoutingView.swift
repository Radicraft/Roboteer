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
    let builds: [BotBuild]
    let record: RivalRecord?
    let scrap: Int
    /// The card the Series screen printed. The report is the long version of it, so the house bot,
    /// the arena and the money come from the same value rather than being worked out twice.
    let next: NextMatch?

    @Binding var chosenID: PersistentIdentifier?
    var onFight: () -> Void
    var onBack: () -> Void

    private var catalogue: Catalogue { Catalogue.shared }

    private var chosen: BotBuild? {
        builds.first { $0.persistentModelID == chosenID } ?? builds.first { !$0.isWrittenOff }
    }

    /// The same gate the Series screen puts on FIGHT: legal, and fit to fight.
    private var canFight: Bool { (chosen?.isValid ?? false) && chosen?.fitnessFault == nil }

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
        HStack(spacing: 10) {
            BackChevron(action: onBack)
            Text("SCOUTING REPORT")
                .font(Stage.display(22))
                .kerning(1.6)
                .foregroundStyle(Stage.text)
            Text((next?.title ?? "").uppercased())
                .font(Stage.label(11))
                .kerning(Stage.Tracking.label(11))
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
                    .kerning(Stage.Tracking.label(12))
                    .foregroundStyle(Stage.type)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // Every number the player can win or be charged is on the screen before FIGHT, and
                // money is a SENTENCE, never a row of bugs (design system section 8). Wave P: there
                // is no entry fee and no purse; a win pays what brief v5 section 3 says it pays.
                if let next {
                    MoneySentence(money(next))

                    HairRule()

                    // Brief v4 section 3: the report names the house bot on duty and says what it
                    // does. One sentence rather than two stat rows, so the panel's own scroll does
                    // not swallow the pips and the grudge line under it.
                    Text("\(next.arenaName). House bot on duty: \(next.houseBotName.asName).")
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.type)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(next.houseBotLine)
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.textFaint)
                        .fixedSize(horizontal: false, vertical: true)

                    HairRule()
                }

                Text(opponent.spec.armourLine)
                    .font(Stage.body(13))
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

                HairRule()

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

    /// "A win pays up to 450 scrap and 450 points. Repairs owing 141." The most a win can pay is
    /// every bonus of brief v5 section 3 at once, which is what "up to" means.
    private func money(_ next: NextMatch) -> [MoneyClause] {
        let rules = next.scrapRules
        let most = rules.base + rules.damageFull + rules.survivor + rules.flawless
        var clauses = [
            MoneyClause("A win pays up to", most, tint: Stage.scrap, tail: " scrap and"),
            MoneyClause("", next.winPoints, tint: Stage.line, tail: " points.")
        ]
        if next.repairsDue > 0 {
            clauses.append(MoneyClause("Repairs owing", next.repairsDue, tint: Stage.danger))
        }
        return clauses
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
            let series = CareerTier.named(record.lastMetTier).index + 1
            let match = record.lastMetRound + 1
            let where_ = match >= SeriesProgress.matchesPerSeries
                ? "the Series \(series) final"
                : "Series \(series), match \(match)"
            line += " Last met in \(where_)."
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

            StageButton("Fight", kind: .primary, enabled: canFight, focusID: "fight", action: onFight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func registerFocus() {
        PadFocus.shared.set(
            [PadItem("fight", enabled: canFight) { onFight() }],
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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(build.name.uppercased())
                        .font(Stage.display(15))
                        .kerning(Stage.Tracking.display(15))
                        .foregroundStyle(Stage.type)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(BuildRules.kilograms(build.totalWeight))
                        .font(Stage.numerals(13))
                        .foregroundStyle(build.isValid ? Stage.typeDim : Stage.danger)
                }
            }
            .frame(width: 168, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                CutRect(8)
                    .fill(Stage.type.opacity(isChosen ? 0.12 : 0.03))
            }
            .overlay {
                CutRect(8)
                    .strokeBorder(isChosen ? Stage.edgeBright : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scrap

/// The scrap balance as a score bug, which is the one shape a number lives in in this system, in
/// the one warm colour chrome is allowed (design system sections 1 and 2).
struct ScrapBadge: View {
    let amount: Int
    var size: CGFloat = 18
    /// The settlement counts its scrap up; a header just prints it.
    var counts: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("SCRAP")
                .font(Stage.label(11))
                .kerning(Stage.Tracking.label(11))
                .foregroundStyle(Stage.typeDim)
            if counts {
                CountingNumber(value: amount, font: Stage.numerals(size), tint: Stage.scrap)
            } else {
                Text("\(amount)")
                    .font(Stage.numerals(size))
                    .foregroundStyle(Stage.scrap)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            ZStack {
                CutRect(8).fill(Stage.glass)
                CutRect(8).strokeBorder(Stage.lineDim, lineWidth: 1)
            }
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(amount) scrap")
    }
}
