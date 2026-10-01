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

    @State private var keepOut = LeaderKeepOut()

    /// Direction A's match result (docs/look/menus-blueprint.html): the result in big stencil top
    /// left with the tally under it, the payout on a plate below, the condition the machine
    /// carries on as the right hand plate with CONTINUE under it, and leader lines from the damaged
    /// parts on the machine itself, in danger when they are badly hurt.
    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 400
            ZStack {
                StageBackdrop(host: host, still: .withBot, dim: 0, shade: .sides)
                StageTouchBlocker()
                StageLeaderLayer(anchors: host.stageAnchors, screen: "result",
                                 leaders: resultLeaders, keepOut: keepOut)

                HStack(alignment: .top, spacing: 16) {
                    summary(compact: compact)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    panel(compact: compact)
                        .frame(width: min(262, (proxy.size.width * 0.33).rounded()))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, compact ? 10 : 14)
                .padding(.bottom, compact ? 4 : 10)
            }
        }
        .statusBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        // Bug 6: this screen's one answer is the pad's, never the screen before the fight.
        .onAppear {
            PadFocus.shared.set(MatchReportView.padItems(onContinue: onContinue), back: nil)
            // Wave C: the stage frames the machine under the gate; a win fires the pyro once.
            host.enterStageScreen("result", cue: report.isWin ? "win" : nil)
        }
    }

    /// The damaged parts: under half, or gone. Danger below a quarter. At most four, worst first.
    private var resultLeaders: [Leader] {
        let hurt = report.parts
            .filter { !$0.key.isEmpty && ($0.condition < 0.5 || report.partsLost.contains($0.label)) }
            .sorted { $0.condition < $1.condition }
            .prefix(4)
        let turns: [(CGFloat, CGFloat)] = [(30, 140), (30, -72), (-10, 90), (-40, -80)]
        return hurt.enumerated().map { index, part in
            let turn = turns[index % turns.count]
            return Leader(id: part.key, target: .part(part.key), title: part.label,
                          value: "\(part.percent)%", danger: part.condition < 0.25,
                          dx: turn.0, dy: turn.1)
        }
    }

    /// The pad's items: CONTINUE and nothing else. B does nothing here, so a report or a reward
    /// can never be skipped past by accident. Static so the self test can check it.
    static func padItems(onContinue: @escaping () -> Void) -> [PadItem] {
        [PadItem("report.continue", action: onContinue)]
    }

    // MARK: - The left hand side

    private func summary(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(PostMatch.word(report.result).capitalized)
                .font(Blueprint.display(compact ? 50 : 60))
                .foregroundStyle(report.result == .loss ? Blueprint.danger : Color.white)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
            Text(PostMatch.outcomeTitle(report))
                .font(Blueprint.display(22))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 2)
            Group {
                Text("\(report.botName) against \(report.opponentName). ") + tallyText
            }
            .font(Blueprint.body(13.5))
            .foregroundStyle(Blueprint.dim)
            .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 300, alignment: .leading)
            .padding(.top, 4)
            .leaderKeepOut(keepOut, "tally")

            // On a 402 pt phone the condition plate needs every row of its column, so the note
            // that sits under CONTINUE on a taller phone joins the tally here instead.
            if compact {
                carryNote
                    .frame(maxWidth: 300, alignment: .leading)
                    .padding(.top, 2)
                    .leaderKeepOut(keepOut, "carry")
            }

            // Wave B judges: a decision on the cards shows the cards, on its own plate, scrolling
            // rather than pushing anything off a short phone.
            if let judges = report.judges {
                ScrollView {
                    JudgesCardView(card: judges)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 6)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.visible)
                .scrollIndicatorsFlash(onAppear: true)
                .padding(10)
                .frame(maxWidth: 300)
                .blueprintPlate()
                .padding(.top, 10)
                .leaderKeepOut(keepOut, "judges")
            } else if report.isWin, let scrap = report.scrap {
                payout(scrap)
                    .frame(width: 220)
                    .padding(.top, compact ? 8 : 14)
                    .leaderKeepOut(keepOut, "payout")
            } else if !report.partsLost.isEmpty {
                Text(lostLine)
                    .font(Blueprint.body(13.5))
                    .foregroundStyle(Blueprint.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300, alignment: .leading)
                    .padding(10)
                    .blueprintPlate()
                    .padding(.top, 10)
                    .leaderKeepOut(keepOut, "lost")
            }

            Spacer(minLength: 0)
        }
    }

    private var carryNote: some View {
        Text("Damage carries into the next match unless it is repaired.")
            .font(Blueprint.body(13))
            .foregroundStyle(Blueprint.dim)
            .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The payout: what the arena tallied, line by line, and what was banked.
    private func payout(_ scrap: ScrapBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Payout").font(Blueprint.ui(12)).foregroundStyle(Blueprint.dim)
                .padding(.bottom, 2)
            BlueprintPayoutRow(label: "Base payout", amount: scrap.base)
            BlueprintPayoutRow(label: "Damage dealt", amount: scrap.damage)
            BlueprintPayoutRow(label: "Survivor", amount: scrap.survivor)
            BlueprintPayoutRow(label: "Flawless", amount: scrap.flawless)
            BlueprintPayoutRow(label: "Banked", amount: scrap.total, total: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .blueprintPlate()
    }

    /// "2:14 on the clock. 41 hits landed, 28 taken.", the figures in the figures face.
    private var tallyText: Text {
        guard report.outcome != "forfeit" else { return Text("The fight was given up, so nothing was tallied.") }
        let figure = Blueprint.inlineFigures(13.5)
        return Text(report.durationText).font(figure).foregroundStyle(Color.white)
            + Text(" on the clock. ")
            + Text("\(report.hitsLanded)").font(figure).foregroundStyle(Color.white)
            + Text(" hits landed, ")
            + Text("\(report.hitsTaken)").font(figure).foregroundStyle(Color.white)
            + Text(" taken.")
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

    /// "Condition now": every part the machine carries on with, one column, then CONTINUE.
    private func panel(compact: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(matchTitle.isEmpty ? "Condition now" : "Condition now. \(matchTitle)")
                    .font(Blueprint.ui(12))
                    .foregroundStyle(Blueprint.dim)
                    .lineLimit(1)
                    .padding(.bottom, 2)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(report.parts) { part in
                            ConditionRow(label: part.label, condition: part.condition)
                                .frame(minHeight: compact ? 22 : 25)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxHeight: .infinity, alignment: .top)
            .fixedSize(horizontal: false, vertical: !compact && report.parts.count <= 11)
            .blueprintPlate()
            .leaderKeepOut(keepOut, "condition")

            StageButton("Continue", kind: .primary, focusID: "report.continue", action: onContinue)
                .leaderKeepOut(keepOut, "continue")

            if !compact {
                carryNote
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
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
/// `-openMatchReport [win|loss|draw|decision]`, `-openRewards [win|series|campaign]`,
/// `-openRetryPrompt [loss|draw|broke|unfit|stranded]`. Continue on the report walks on to the screen that
/// follows it, so the whole sequence can be checked in one launch.
enum PostMatchQA {

    enum Screen: Equatable {
        case report(String)
        case rewards(String)
        case retry(String)
        /// `-openResultSheet decision`: the quick fight ResultSheet after a judges decision.
        case sheet(String)
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
        if ArenaHost.hasLaunchFlag("-openResultSheet") {
            return .sheet(ArenaHost.launchArgument("-openResultSheet") ?? "decision")
        }
        return nil
    }

    static let matchTitle = "Series 2, match 3"

    /// A real machine's worth of condition, in the order `ProgressionEngine.partConditions` builds
    /// it: weapon, drive, the four wheels, the four armour faces, the hull.
    static func report(_ variant: String) -> MatchReport {
        // `decision`: lost on the judges, with the card (wave B judges).
        if variant == "decision" {
            var base = Self.report("loss")
            base.outcome = "judges"
            base.judges = judgesCard
            return base
        }
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
            parts: parts.enumerated().map { index, part in
                PartCondition(label: part.0, condition: part.1, startCondition: 1,
                              key: index == 0 ? "weapon" : (index == 1 ? "drive"
                                   : (index == parts.count - 1 ? "chassis" : PartCondition.key(forLabel: part.0))))
            },
            partsLost: ["Rear left wheel", "Sides armour"],
            botName: "Tinribs",
            opponentName: "Clatterbox",
            scrap: ScrapBreakdown(base: 150, damage: 118, survivor: 75, flawless: 0)
        )
    }

    /// A close decision lost: more damage done, less control, the words the arena's detail makes.
    static let judgesCard = JudgesCard(
        myName: "Tinribs", theirName: "Clatterbox",
        rows: [
            JudgesCard.Row(title: "Damage", outOf: 5, mine: 3.1, theirs: 1.9),
            JudgesCard.Row(title: "Control", outOf: 3, mine: 0.2, theirs: 2.8),
            JudgesCard.Row(title: "Aggression", outOf: 2, mine: 0.6, theirs: 1.4)
        ],
        myTotal: 3.9, theirTotal: 6.1,
        reasons: [
            "Tinribs lost 18% of its machine. Clatterbox lost 26% of its machine.",
            "Clatterbox had Tinribs on its back, in the air or on the spikes for 24 s and shoved it into a hazard once.",
            "Tinribs drove in for 20 s, Clatterbox for 41 s. Blows landed: 6 to 11."
        ],
        verdict: "Clatterbox wins on the cards, 6.1 to 3.9."
    )

    /// The same decision as a whole arena result, for the quick fight ResultSheet
    /// (`-openResultSheet decision`): the scores and the detail the card's words are made from.
    static let judgesResult: [String: Any] = [
        "schema": 1, "duration_s": 180.0,
        "outcome": ["type": "judges", "winner": "ai-1", "loser": "player-1", "at_s": 180.0],
        "damage": [
            "player-1": ["wheels": [0.71, 0.83, 0.0, 0.66], "weapon": 0.4, "drive": 0.55, "core": 0.9,
                         "armour": ["front": 0.62, "sides": 0.1, "rear": 0.94, "top": 1.0]],
            "ai-1": ["wheels": [0.5, 1.0, 0.8, 1.0], "weapon": 0.3, "drive": 0.7, "core": 0.85,
                     "armour": ["front": 0.4, "sides": 0.9, "rear": 1.0, "top": 0.8]]
        ],
        "scrap": ["player-1": 0, "ai-1": 0],
        "judges": ["player-1": ["damage": 3.1, "control": 0.2, "aggression": 0.6],
                   "ai-1": ["damage": 1.9, "control": 2.8, "aggression": 1.4]],
        "judges_detail": ["player-1": ["lost_pct": 18, "parts_out": 0, "control_s": 0, "payoffs": 0,
                                       "payoff_s": 0, "aggression_s": 20, "blows": 6],
                          "ai-1": ["lost_pct": 26, "parts_out": 0, "control_s": 24, "payoffs": 1,
                                   "payoff_s": 8, "aggression_s": 41, "blows": 11]]
    ]

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
            newlyUnlocked: ProgressionEngine.newlyUnlocked(from: before.level, to: after.level,
                                                          owned: ProgressionEngine.startingOwned),
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
            case .sheet:
                ResultSheet(host: host, result: FightResult(object: PostMatchQA.judgesResult), player: nil) {
                    spikeLog.info("QA: back to garage")
                }
                .onAppear {
                    host.botNames = ["player-1": "Tinribs", "ai-1": "Clatterbox"]
                    host.botOrder = ["player-1", "ai-1"]
                }
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
        // `unfit` is a loss that left the core destroyed with the bill affordable; `stranded` is
        // the same with too little scrap to pay it (bug 4: RETRY is off and says why).
        let unfit = variant == "unfit" || variant == "stranded"
        let scrap = (variant == "broke" || variant == "stranded") ? 90 : 620
        return RetryPromptView(
            host: host,
            report: PostMatchQA.report(variant == "draw" ? "draw" : "loss"),
            repairBill: PostMatchQA.bill(),
            scrap: scrap,
            matchTitle: PostMatchQA.matchTitle,
            attempts: 3,
            retryBlock: unfit
                ? ProgressionEngine.retryBlock(fault: "Core destroyed", legal: true, ownership: nil,
                                               repairBill: PostMatchQA.bill().total, scrap: scrap,
                                               canPatch: variant == "stranded")
                : nil,
            onPatchAndRetry: variant == "stranded" ? { spikeLog.info("QA: patch and retry") } : nil,
            onRetry: { spikeLog.info("QA: retry") },
            onRepairAndRetry: { spikeLog.info("QA: repair and retry") },
            onGarage: { spikeLog.info("QA: garage") }
        )
    }
}

// MARK: - The judges' card (wave B judges)

/// Why a fight went the way it did on the cards, in the arena's own numbers and in words.
/// Owner, 2026-09-27: "i virtually had no damage one game but the judges decided the opponent
/// won". The report used to say "Lost on the judges" and nothing else. Now it shows the three
/// columns (the judges split ten points: damage 5, control 3, aggression 2) and a sentence for
/// each, so a decision can be read and argued with. docs/wave-b-judges-notes.md has the rules.
struct JudgesCard: Equatable {

    struct Row: Equatable, Identifiable {
        var title: String
        var outOf: Double
        var mine: Double
        var theirs: Double
        var id: String { title }
    }

    var myName: String
    var theirName: String
    var rows: [Row]
    var myTotal: Double
    var theirTotal: Double
    /// One sentence a column: what each machine lost, who held whom down, who drove in.
    var reasons: [String]
    /// "Tinribs wins on the cards, 5.7 to 4.3."
    var verdict: String

    static let damagePoints = 5.0
    static let controlPoints = 3.0
    static let aggressionPoints = 2.0

    /// Nil when the result carries no card for one of the two machines.
    static func make(result: FightResult, myID: String, myName: String, theirName: String) -> JudgesCard? {
        guard let mine = result.judges[myID],
              let theirID = result.judges.keys.sorted().first(where: { $0 != myID }),
              let theirs = result.judges[theirID] else { return nil }
        let myDetail = result.judgesDetail[myID] ?? FightResult.JudgeDetail()
        let theirDetail = result.judgesDetail[theirID] ?? FightResult.JudgeDetail()
        let rows = [
            Row(title: "Damage", outOf: damagePoints, mine: mine.damage, theirs: theirs.damage),
            Row(title: "Control", outOf: controlPoints, mine: mine.control, theirs: theirs.control),
            Row(title: "Aggression", outOf: aggressionPoints, mine: mine.aggression, theirs: theirs.aggression)
        ]
        var reasons: [String] = []
        if !result.judgesDetail.isEmpty {
            reasons = [
                damageWords(myName, myDetail, result.partsLost[myID] ?? [],
                            theirName, theirDetail, result.partsLost[theirID] ?? []),
                controlWords(myName, myDetail, theirName, theirDetail),
                aggressionWords(myName, myDetail, theirName, theirDetail)
            ]
        }
        let winner = result.outcome.winner == myID ? myName
            : (result.outcome.winner == theirID ? theirName : "")
        return JudgesCard(
            myName: myName, theirName: theirName, rows: rows,
            myTotal: mine.total, theirTotal: theirs.total,
            reasons: reasons,
            verdict: verdictWords(winner: winner, myName: myName, myTotal: mine.total, theirTotal: theirs.total)
        )
    }

    /// "5.7", "5", "0.5": one decimal, and none for a whole number.
    static func points(_ value: Double) -> String {
        let tenths = (value * 10).rounded() / 10
        if tenths == tenths.rounded() { return String(Int(tenths)) }
        return String(format: "%.1f", tenths)
    }

    static func seconds(_ value: Double) -> String { "\(Int(value.rounded())) s" }

    /// "Tinribs lost 14% of its machine. Penny Dread lost 20%, and its weapon."
    static func damageWords(_ myName: String, _ mine: FightResult.JudgeDetail, _ myLost: [FightResult.PartLost],
                            _ theirName: String, _ theirs: FightResult.JudgeDetail,
                            _ theirLost: [FightResult.PartLost]) -> String {
        if mine.lostPercent == 0 && theirs.lostPercent == 0 && myLost.isEmpty && theirLost.isEmpty {
            return "Neither machine took any damage."
        }
        return lossSentence(myName, mine, myLost) + " " + lossSentence(theirName, theirs, theirLost)
    }

    private static func lossSentence(_ name: String, _ detail: FightResult.JudgeDetail,
                                     _ lost: [FightResult.PartLost]) -> String {
        // A jammed or cooked weapon is not knocked out (the judges do not count it); a dead
        // drive is, the arena calls it disabled because nothing came off the machine.
        let parts = lost.filter { $0.isDestroyed || $0.part == "drive" }.map { $0.label.lowercased() }
        var sentence = "\(name) lost \(detail.lostPercent)% of its machine"
        if !parts.isEmpty { sentence += ", and its \(PostMatch.list(parts))" }
        return sentence + "."
    }

    /// "Penny Dread had Tinribs on its back, in the air or on the spikes for 21 s."
    static func controlWords(_ myName: String, _ mine: FightResult.JudgeDetail,
                             _ theirName: String, _ theirs: FightResult.JudgeDetail) -> String {
        let lines = [controlSentence(myName, mine, theirName), controlSentence(theirName, theirs, myName)]
            .compactMap { $0 }
        if lines.isEmpty { return "Neither machine had the other on its back or on a hazard." }
        return lines.joined(separator: " ")
    }

    private static func controlSentence(_ name: String, _ detail: FightResult.JudgeDetail,
                                        _ other: String) -> String? {
        var clauses: [String] = []
        if detail.controlSeconds >= 0.5 {
            clauses.append("had \(other) on its back, in the air or on the spikes for \(seconds(detail.controlSeconds))")
        }
        if detail.payoffs > 0 {
            let times = detail.payoffs == 1 ? "once" : (detail.payoffs == 2 ? "twice" : "\(detail.payoffs) times")
            clauses.append("shoved it into a hazard \(times)")
        }
        guard !clauses.isEmpty else { return nil }
        return "\(name) " + clauses.joined(separator: " and ") + "."
    }

    /// "Tinribs drove in for 36 s, Penny Dread for 27 s. Blows landed: 4 to 2."
    static func aggressionWords(_ myName: String, _ mine: FightResult.JudgeDetail,
                                _ theirName: String, _ theirs: FightResult.JudgeDetail) -> String {
        var sentence = "\(myName) drove in for \(seconds(mine.aggressionSeconds)), \(theirName) for \(seconds(theirs.aggressionSeconds))."
        if mine.blows > 0 || theirs.blows > 0 {
            sentence += " Blows landed: \(mine.blows) to \(theirs.blows)."
        }
        return sentence
    }

    static func verdictWords(winner: String, myName: String, myTotal: Double, theirTotal: Double) -> String {
        guard !winner.isEmpty else { return "No winner was recorded." }
        if abs(myTotal - theirTotal) < 0.05 {
            return "Level at \(points(myTotal)) each. A tie goes to damage, then control: \(winner) has it."
        }
        let high = max(myTotal, theirTotal)
        let low = min(myTotal, theirTotal)
        return "\(winner) wins on the cards, \(points(high)) to \(points(low))."
    }
}

/// The card on screen: three columns and a total for each machine, then the words. Broadcast
/// look, no line accents: the rows are the Stage type on the panel glass, and the column the
/// player won is in `win`, the one they lost in the body colour.
struct JudgesCardView: View {

    let card: JudgesCard
    var heading: String = "How the judges scored it"

    /// Wide (the quick fight ResultSheet, the whole width of the phone): the numbers on the
    /// left and the words beside them, so the reasons are above the fold of a 402 pt phone.
    var wide: Bool = false

    var body: some View {
        if wide {
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    StageHeading(heading)
                    scores
                }
                .fixedSize()
                words
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                StageHeading(heading)
                scores
                words
            }
        }
    }

    private var scores: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
            GridRow {
                Text("TEN POINTS")
                    .font(Stage.label(11))
                    .kerning(Stage.Tracking.label(11))
                    .foregroundStyle(Stage.textFaint)
                name(card.myName)
                name(card.theirName)
            }
            ForEach(card.rows) { row in
                GridRow {
                    Text("\(row.title.uppercased()) OF \(JudgesCard.points(row.outOf))")
                        .font(Stage.label(11))
                        .kerning(Stage.Tracking.label(11))
                        .foregroundStyle(Stage.typeDim)
                    score(row.mine, leads: row.mine > row.theirs + 0.05)
                    score(row.theirs, leads: row.theirs > row.mine + 0.05)
                }
            }
            GridRow {
                Text("TOTAL")
                    .font(Stage.label(11, weight: .bold))
                    .kerning(Stage.Tracking.label(11))
                    .foregroundStyle(Stage.type)
                score(card.myTotal, leads: card.myTotal > card.theirTotal + 0.05, size: 15)
                score(card.theirTotal, leads: card.theirTotal > card.myTotal + 0.05, size: 15)
            }
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.verdict)
                .font(Stage.body(13))
                .foregroundStyle(Stage.type)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(card.reasons.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.typeDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func name(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Stage.label(11, weight: .bold))
            .kerning(Stage.Tracking.label(11))
            .foregroundStyle(Stage.textFaint)
            .lineLimit(1)
            .minimumScaleFactor(BroadcastType.floorScale(.label, size: 11, wanted: 0.8))
    }

    private func score(_ value: Double, leads: Bool, size: CGFloat = 13) -> some View {
        Text(JudgesCard.points(value))
            .font(Stage.numerals(size))
            .foregroundStyle(leads ? Stage.win : Stage.type)
            .figureLine(size)
    }
}
