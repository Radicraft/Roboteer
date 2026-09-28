//
//  RewardsView.swift
//  Brief v5 section 6, mockup W1 (`docs/look/postmatch-options.html`): the payoff screen, reached
//  only on a win. One panel, read top to bottom in the order the brief names the two tracks: the
//  four scrap lines counting up to a banked total, then the Level bar filling under it, then what
//  that Level opened in the shop.
//
//  Nothing here decides anything. `CareerStore.settleMatch` has already banked the scrap and the
//  points and moved the campaign on; `Rewards` is the record of what it did.
//

import SwiftUI

struct RewardsView: View {

    @Bindable var host: ArenaHost
    let rewards: Rewards
    /// "Series 2, match 3", from `NextMatch.title`. Empty for a fight with no card behind it.
    var matchTitle: String = ""
    var onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                StageBackdrop(host: host, still: .withBot, dim: 0.34)
                StageTouchBlocker()

                HStack(alignment: .top, spacing: 14) {
                    summary
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    panel
                        .frame(width: StageLayout.columnWidth(proxy.size.width))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, Stage.Space.gutter + 6)
                .padding(.vertical, 14)
            }
        }
        .statusBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        // Bug 6: this screen's one answer is the pad's, never the screen before the fight.
        .onAppear {
            PadFocus.shared.set(RewardsView.padItems(onContinue: onContinue), back: nil)
            host.enterStageScreen("rewards")
        }
    }

    /// The pad's items: CONTINUE and nothing else. B does nothing here, so a report or a reward
    /// can never be skipped past by accident. Static so the self test can check it.
    static func padItems(onContinue: @escaping () -> Void) -> [PadItem] {
        [PadItem("rewards.continue", action: onContinue)]
    }

    // MARK: - The left hand side

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            LowerThird(bar: Stage.win, entersFrom: .leading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("WON")
                        .font(Stage.display(30))
                        .kerning(Stage.Tracking.display(30))
                        .foregroundStyle(Stage.win)
                    Text(progressLine.uppercased())
                        .font(Stage.label(11))
                        .kerning(Stage.Tracking.label(11))
                        .foregroundStyle(Stage.typeDim)
                        .lineLimit(2)
                        .minimumScaleFactor(BroadcastType.floorScale(.label, size: 11, wanted: 0.7))
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Text("Scrap is banked on a win only, and this one is banked.")
                .font(Stage.body(13))
                .foregroundStyle(Stage.typeDim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 10)

            Spacer(minLength: 0)
        }
    }

    /// Where the campaign stands after this win, in one line.
    private var progressLine: String {
        // The title defence (owner decision 8) speaks in reigns, not Series.
        if !rewards.headline.isEmpty { return rewards.headline }
        if rewards.finishedCampaign {
            return "Every Series is won. Any match can be fought again from the Series screen."
        }
        if rewards.hitTheWall {
            return "Series \(wonSeriesNumber) is complete. The next Series is in the full game."
        }
        if rewards.finishedSeries {
            return "Series \(wonSeriesNumber) is complete. Series \(wonSeriesNumber + 1) is open."
        }
        return rewards.series.line
    }

    /// The Series this win belongs to. When the win opened the next Series the progress has
    /// already moved on, so the Series just taken is the one before it.
    private var wonSeriesNumber: Int {
        let number = rewards.series.seriesNumber
        let moved = rewards.finishedSeries && !rewards.hitTheWall && !rewards.finishedCampaign
        return moved ? max(1, number - 1) : number
    }

    // MARK: - The one panel

    private var panel: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                PanelLabel("Rewards", accent: matchTitle)
                HairRule()

                VStack(alignment: .leading, spacing: 4) {
                    LedgerRow(label: "Base payout", amount: rewards.scrap.base)
                    LedgerRow(label: "Damage dealt", amount: rewards.scrap.damage)
                    LedgerRow(label: "Survivor", amount: rewards.scrap.survivor)
                    LedgerRow(label: "Flawless", amount: rewards.scrap.flawless)
                    // Owner decision 3: a replay that earned a new medal pays the whole match.
                    if rewards.medalTopUp > 0 {
                        LedgerRow(label: "Medal bonus", amount: rewards.medalTopUp)
                    }
                }

                HairRule()
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    StageHeading("Banked")
                    Spacer(minLength: 6)
                    CountingNumber(value: rewards.bankedTotal, font: Stage.numerals(30), tint: Stage.scrap)
                }

                if !rewards.medals.isEmpty {
                    medalsLine
                }

                level
                    .padding(.top, 2)

                opened
                Spacer(minLength: 0)

                StageButton("Continue", kind: .primary, focusID: "rewards.continue", action: onContinue)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Medals

    /// "Medals: Win, Survivor. New: Survivor." One plain line; the stamps are the owner's to
    /// choose (docs/look/progression-screens-v1.html).
    private var medalsLine: some View {
        let names = rewards.medals.map(\.name)
        let fresh = rewards.newMedals.map(\.name)
        var line = words("Medals: ") + lit(PostMatch.list(names)) + words(".")
        if !fresh.isEmpty, fresh.count < names.count {
            line = line + words(" New: ") + lit(PostMatch.list(fresh)) + words(".")
        } else if !fresh.isEmpty, rewards.medalTopUp > 0 {
            line = line + words(" New medals pay the match in full.")
        }
        return line.fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Level

    private var level: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                PanelLabel("Level", accent: "\(rewards.levelAfter.level)")
                Spacer(minLength: 6)
                Text("\(rewards.levelPoints) points earned")
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.typeDim)
                    .lineLimit(1)
                    .minimumScaleFactor(BroadcastType.floorScale(.body, size: 13, wanted: 0.7))
            }
            LevelGainBar(
                from: rewards.levelBefore.fraction,
                to: rewards.levelAfter.fraction,
                wraps: rewards.levelsGained > 0
            )
            Text(levelFootnote)
                .font(Stage.body(13))
                .foregroundStyle(Stage.typeDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var levelFootnote: String {
        let after = rewards.levelAfter
        if after.isCapped { return "Level \(after.cap) is the top of the ladder." }
        let remaining = max(0, after.pointsPerLevel - after.pointsIntoLevel)
        return "\(remaining) points to Level \(after.level + 1)."
    }

    // MARK: - What this Level opened

    @ViewBuilder
    private var opened: some View {
        if partNames.isEmpty && paintNames.isEmpty {
            Text(nothingNewLine)
                .font(Stage.body(13))
                .foregroundStyle(Stage.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                if !partNames.isEmpty {
                    (words("New in the shop: ") + lit(PostMatch.list(partNames)) + words("."))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !paintNames.isEmpty {
                    (words(paintNames.count == 1 ? "New paint job: " : "New paint jobs: ")
                        + lit(PostMatch.list(paintNames)) + words("."))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var partNames: [String] {
        rewards.newlyUnlocked.map { ProgressionEngine.displayName($0) }
    }

    private var paintNames: [String] {
        let all = ProgressionEngine.paintJobs(level: rewards.levelAfter.level)
        return rewards.newPaintJobs.compactMap { id in all.first { $0.id == id }?.name }
    }

    /// When nothing opened, the honest next milestone rather than an empty space.
    private var nothingNewLine: String {
        let level = rewards.levelAfter.level
        let next = ProgressionEngine.progression.levelRequired.values.filter { $0 > level }.min()
        guard let next else { return "Every part on the ladder is already open to you." }
        return "Nothing new opens until Level \(next)."
    }

    private func words(_ text: String) -> Text {
        Text(text).font(Stage.body(13)).foregroundStyle(Stage.type)
    }

    private func lit(_ text: String) -> Text {
        Text(text).font(Stage.body(13, weight: .semibold)).foregroundStyle(Stage.line)
    }
}
