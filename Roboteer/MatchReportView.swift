//
//  MatchReportView.swift
//  Brief v5 section 5, mockup R1 (`docs/look/postmatch-options.html`): the factual tally shown the
//  moment a career match ends, before any rewards. The result, the clock and the hits read left to
//  right beside the machine, which stands battered on the stage behind them; the one panel is the
//  part by part truth, which is the only thing here that needs a grid.
//
//  It replaces `DamageAssessmentView`: there is no repair button and no write off offer any more,
//  because repairs are the player's own choice on the Series screen and from the retry prompt
//  (brief v5 section 9.4). `CareerStore.settleMatch` has already carried the damage home and
//  banked whatever a win banked by the time this screen appears; this screen only prints.
//

import SwiftUI

struct MatchReportView: View {

    @Bindable var host: ArenaHost
    let report: MatchReport
    /// "Series 2, match 3", from `NextMatch.title`. Empty for a fight with no card behind it.
    var matchTitle: String = ""
    var onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // The machine that just fought is still on the stage behind this, so the wash is
                // light: the owner reads what is broken off it while looking at it.
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
    }

    // MARK: - The left hand side

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            LowerThird(bar: PostMatch.bar(report.result), entersFrom: .leading) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(PostMatch.word(report.result))
                            .font(Stage.display(34))
                            .kerning(Stage.Tracking.display(34))
                            .foregroundStyle(PostMatch.tint(report.result))
                        Text(PostMatch.outcomeTitle(report).uppercased())
                            .font(Stage.display(17))
                            .kerning(Stage.Tracking.display(17))
                            .foregroundStyle(Stage.type)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Text("\(report.botName.uppercased()) AGAINST \(report.opponentName.uppercased())")
                        .font(Stage.label(11))
                        .kerning(Stage.Tracking.label(11))
                        .foregroundStyle(Stage.typeDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text(tallyLine)
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.typeDim)
                    .fixedSize(horizontal: false, vertical: true)
                Text(lostLine)
                    .font(Stage.body(13))
                    .foregroundStyle(report.partsLost.isEmpty ? Stage.textFaint : Stage.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 10)

            Spacer(minLength: 0)
        }
    }

    /// "2:14 on the clock. 41 hits landed, 28 taken."
    private var tallyLine: String {
        guard report.outcome != "forfeit" else {
            return "The fight was given up, so nothing was tallied."
        }
        return "\(report.durationText) on the clock. \(report.hitsLanded) hits landed, \(report.hitsTaken) taken."
    }

    /// The parts destroyed or disabled, named the way the arena named them.
    private var lostLine: String {
        guard !report.partsLost.isEmpty else { return "Nothing came off the machine." }
        return "Destroyed or disabled: \(PostMatch.list(report.partsLost))."
    }

    // MARK: - The one panel

    private var panel: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    PanelLabel("Match report", accent: matchTitle)
                    Spacer(minLength: 6)
                    StageHeading("Condition now")
                }
                HairRule()

                // The panel hugs the list, so a four wheel machine's eleven rows do not leave a
                // hole above the button. A machine with more parts than the panel is tall (six
                // wheels and every armour face) scrolls instead, and then the panel takes the
                // whole height, so CONTINUE can never be pushed off the bottom.
                if needsScroll {
                    ScrollView {
                        conditionColumns
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: .infinity)
                } else {
                    conditionColumns
                }

                HairRule()
                Text("Damage carries into the next match unless it is repaired.")
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.textFaint)
                    .fixedSize(horizontal: false, vertical: true)

                StageButton("Continue", kind: .primary, focusID: "report.continue", action: onContinue)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: needsScroll ? .infinity : nil, alignment: .top)
    }

    private var conditionColumns: some View {
        HStack(alignment: .top, spacing: 16) {
            column(columns.0)
            column(columns.1)
        }
        .padding(.trailing, 2)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var columns: ([PartCondition], [PartCondition]) { PostMatch.half(report.parts) }

    /// Eight rows a column is the most the panel holds beside the banner on a 402 pt tall phone.
    private var needsScroll: Bool { columns.0.count > 8 }

    private func column(_ parts: [PartCondition]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(parts) { part in
                ConditionRow(label: part.label, condition: part.condition)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - The words the three post-match screens share

/// The one place a result is turned into words and colour, so the report, the rewards screen and
/// the retry prompt cannot disagree about what just happened.
enum PostMatch {

    static func word(_ result: MatchReport.Result) -> String {
        switch result {
        case .win: return "WON"
        case .loss: return "LOST"
        case .draw: return "DRAW"
        }
    }

    static func tint(_ result: MatchReport.Result) -> Color {
        switch result {
        case .win: return Stage.win
        case .loss: return Stage.danger
        case .draw: return Stage.type
        }
    }

    static func bar(_ result: MatchReport.Result) -> Color {
        switch result {
        case .win: return Stage.win
        case .loss: return Stage.danger
        case .draw: return Stage.lineDim
        }
    }

    /// What kind of win or loss it was, in the arena's own vocabulary
    /// (`ko`, `out_of_arena`, `component_kill`, `judges`, `timeout`, `forfeit`).
    static func outcomeTitle(_ report: MatchReport) -> String {
        switch (report.result, report.outcome) {
        case (.win, "ko"): return "Knockout win"
        case (.win, "out_of_arena"): return "Thrown out, you win"
        case (.win, "component_kill"): return "Core kill"
        case (.win, _): return "Win on the judges"
        case (.draw, _): return "Drawn on the judges"
        case (.loss, "ko"): return "Knocked out"
        case (.loss, "out_of_arena"): return "Out of the arena"
        case (.loss, "component_kill"): return "Core destroyed"
        case (.loss, "forfeit"): return "Fight given up"
        case (.loss, _): return "Lost on the judges"
        }
    }

    /// "the flipper, the drive and the rear left wheel", as a sentence rather than as a list.
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
        }
    }

    /// The condition list in two columns, the first column taking the odd part of an odd count.
    static func half(_ parts: [PartCondition]) -> ([PartCondition], [PartCondition]) {
        guard parts.count > 1 else { return (parts, []) }
        let split = (parts.count + 1) / 2
        return (Array(parts.prefix(split)), Array(parts.dropFirst(split)))
    }

    /// "third". Words to ten, then the numeral, because "14th" reads better than spelling it out.
    static func ordinal(_ value: Int) -> String {
        let words = ["", "first", "second", "third", "fourth", "fifth",
                     "sixth", "seventh", "eighth", "ninth", "tenth"]
        guard value >= 1 else { return "first" }
        if value < words.count { return words[value] }
        let suffix: String
        switch value % 10 {
        case 1 where value % 100 != 11: suffix = "st"
        case 2 where value % 100 != 12: suffix = "nd"
        case 3 where value % 100 != 13: suffix = "rd"
        default: suffix = "th"
        }
        return "\(value)\(suffix)"
    }
}

// MARK: - The QA fixture (docs/qa-launch-flags.md)

/// The three post-match screens opened straight from a launch argument with fixture data, so they
/// can be read and screenshotted without fighting a match first. Exactly the same job
/// `CareerStore.loadFixtureIfRequested` does for the garage.
///
/// `-openMatchReport [win|loss|draw]`, `-openRewards [win|series|campaign]`,
/// `-openRetryPrompt [loss|draw|broke]`. Continue on the report walks on to the screen that
/// follows it, so the whole sequence can be checked in one launch.
enum PostMatchQA {

    enum Screen: Equatable {
        case report(String)
        case rewards(String)
        case retry(String)
    }

    /// Nil in every ordinary launch.
    static var requested: Screen? {
        if ArenaHost.hasLaunchFlag("-openMatchReport") {
            return .report(ArenaHost.launchArgument("-openMatchReport") ?? "win")
        }
        if ArenaHost.hasLaunchFlag("-openRewards") {
            return .rewards(ArenaHost.launchArgument("-openRewards") ?? "win")
        }
        if ArenaHost.hasLaunchFlag("-openRetryPrompt") {
            return .retry(ArenaHost.launchArgument("-openRetryPrompt") ?? "loss")
        }
        return nil
    }

    static let matchTitle = "Series 2, match 3"

    /// A real machine's worth of condition, in the order `ProgressionEngine.partConditions` builds
    /// it: weapon, drive, the four wheels, the four armour faces, the hull.
    static func report(_ variant: String) -> MatchReport {
        let result: MatchReport.Result = variant == "loss" ? .loss : (variant == "draw" ? .draw : .win)
        let parts: [(String, Double)] = [
            ("Flipper", 0.40),
            ("Four wheel drive", 0.55),
            ("Front left wheel", 0.71),
            ("Front right wheel", 0.83),
            ("Rear left wheel", 0.0),
            ("Rear right wheel", 0.66),
            ("Front armour", 0.62),
            ("Sides armour", 0.10),
            ("Rear armour", 0.94),
            ("Top armour", 1.0),
            ("Wedge", 0.88)
        ]
        return MatchReport(
            result: result,
            outcome: result == .draw ? "judges" : "ko",
            durationSeconds: 134,
            hitsLanded: result == .win ? 41 : 19,
            hitsTaken: result == .win ? 28 : 46,
            parts: parts.map { PartCondition(label: $0.0, condition: $0.1, startCondition: 1) },
            partsLost: ["Rear left wheel", "Sides armour"],
            botName: "Tinribs",
            opponentName: "Clatterbox",
            scrap: ScrapBreakdown(base: 150, damage: 118, survivor: 75, flawless: 0)
        )
    }

    /// The rewards of that win, with the Level, the unlocks and the paint jobs read out of the
    /// real catalogue rather than invented, so the screen shows what the ladder actually opens.
    static func rewards(_ variant: String) -> Rewards {
        let before = ProgressionEngine.level(points: 1250)
        let points = 450
        let after = ProgressionEngine.level(points: 1250 + points)
        let finishedSeries = variant == "series" || variant == "campaign"
        return Rewards(
            scrap: ScrapBreakdown(base: 150, damage: 118, survivor: 75, flawless: 0),
            levelPoints: points,
            levelBefore: before,
            levelAfter: after,
            series: SeriesProgress(
                seriesIndex: variant == "campaign" ? 4 : (variant == "series" ? 2 : 1),
                matchIndex: finishedSeries ? (variant == "campaign" ? 4 : 0) : 3,
                attempts: 0,
                campaignComplete: variant == "campaign"
            ),
            newlyUnlocked: ProgressionEngine.newlyUnlocked(from: before.level, to: after.level),
            newPaintJobs: ProgressionEngine.newPaintJobs(from: before.level, to: after.level),
            finishedSeries: finishedSeries,
            finishedCampaign: variant == "campaign",
            hitTheWall: false
        )
    }

    /// A bill the size a three minute knockout leaves behind.
    static func bill() -> RepairBill {
        RepairBill(
            items: [
                RepairBill.Item(id: "weapon", label: "Flipper", lost: 0.6, cost: 74),
                RepairBill.Item(id: "drive", label: "Four wheel drive", lost: 0.45, cost: 52),
                RepairBill.Item(id: "wheel_2", label: "Rear left wheel", lost: 1, cost: 26),
                RepairBill.Item(id: "armour_sides", label: "Sides armour", lost: 0.9, cost: 32)
            ],
            total: 184,
            buildValue: 820,
            isWriteOff: false,
            scrapForParts: 246
        )
    }
}

/// The screen a QA launch argument asked for, with the fixture behind it.
struct PostMatchQAView: View {

    @Bindable var host: ArenaHost
    let screen: PostMatchQA.Screen

    @State private var step = 0

    var body: some View {
        ZStack {
            switch screen {
            case .report(let variant):
                if step == 0 {
                    MatchReportView(
                        host: host,
                        report: PostMatchQA.report(variant),
                        matchTitle: PostMatchQA.matchTitle
                    ) { step = 1 }
                } else if variant == "win" {
                    rewards("win")
                } else {
                    retry(variant)
                }
            case .rewards(let variant):
                rewards(variant)
            case .retry(let variant):
                retry(variant)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func rewards(_ variant: String) -> some View {
        RewardsView(
            host: host,
            rewards: PostMatchQA.rewards(variant),
            matchTitle: PostMatchQA.matchTitle
        ) {
            spikeLog.info("QA: rewards continued")
        }
    }

    private func retry(_ variant: String) -> some View {
        RetryPromptView(
            host: host,
            report: PostMatchQA.report(variant == "draw" ? "draw" : "loss"),
            repairBill: PostMatchQA.bill(),
            scrap: variant == "broke" ? 90 : 620,
            matchTitle: PostMatchQA.matchTitle,
            attempts: 3,
            onRetry: { spikeLog.info("QA: retry") },
            onRepairAndRetry: { spikeLog.info("QA: repair and retry") },
            onGarage: { spikeLog.info("QA: garage") }
        )
    }
}
