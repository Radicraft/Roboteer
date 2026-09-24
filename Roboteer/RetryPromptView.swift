//
//  RetryPromptView.swift
//  Brief v5 sections 2 and 9.1, mockup T1 (`docs/look/postmatch-options.html`): what a loss or a
//  draw leads to. The match report has just printed every number, so this screen exists to ask one
//  question, and it asks it with no panel at all: the losing banner, three short lines, and the
//  two answers stacked on the right with the garage as a link.
//
//  A loss costs nothing but the match's scrap. The same opponent in the same arena, on a new seed,
//  so the fight is not identical; the machine goes back in with the damage it has unless the
//  player pays the bill first.
//

import SwiftUI

struct RetryPromptView: View {

    @Bindable var host: ArenaHost
    let report: MatchReport
    let repairBill: RepairBill
    let scrap: Int
    /// "Series 2, match 3", from `NextMatch.title`. Empty for a fight with no card behind it.
    var matchTitle: String = ""
    /// How many attempts have been made at this match, this one included (`CareerState.attempts`
    /// after the match was settled). Two or more is worth saying out loud; one is not.
    var attempts: Int = 0
    /// Why the machine cannot go straight back in (`ProgressionEngine.retryBlock`), or nil when
    /// it can. RETRY is off while this is set, and the sentence names the fix (bug 4).
    var retryBlock: String? = nil
    /// True when paying the bill would clear `retryBlock` (the fault is damage, not legality or
    /// ownership), so "Repair and retry" stays on.
    var repairClearsBlock: Bool = true
    var onRetry: () -> Void
    var onRepairAndRetry: () -> Void
    var onGarage: () -> Void

    private var forfeited: Int { report.scrap?.total ?? 0 }
    private var canAffordRepair: Bool { scrap >= repairBill.total }
    private var canRetry: Bool { retryBlock == nil }
    private var canRepairAndRetry: Bool { canAffordRepair && (retryBlock == nil || repairClearsBlock) }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                StageBackdrop(host: host, still: .withBot, dim: 0.34)
                StageTouchBlocker()

                HStack(alignment: .top, spacing: 18) {
                    summary
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    answers
                        .frame(width: min(320, max(240, proxy.size.width * 0.35)))
                        .padding(.top, 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, Stage.Space.gutter + 6)
                .padding(.vertical, 16)
            }
        }
        .statusBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        // Bug 6: the pad lands on this screen's own answers, never the screen before the fight.
        .onAppear { registerFocus() }
        .onChange(of: retryBlock) { _, _ in registerFocus() }
    }

    private func registerFocus() {
        PadFocus.shared.set(
            RetryPromptView.padItems(
                canRetry: canRetry,
                showsRepair: !repairBill.isPristine,
                canRepairAndRetry: canRepairAndRetry,
                onRetry: onRetry,
                onRepairAndRetry: onRepairAndRetry,
                onGarage: onGarage
            ),
            back: onGarage
        )
    }

    /// The pad's items, in reading order. Static so the self test can check them.
    static func padItems(
        canRetry: Bool,
        showsRepair: Bool,
        canRepairAndRetry: Bool,
        onRetry: @escaping () -> Void,
        onRepairAndRetry: @escaping () -> Void,
        onGarage: @escaping () -> Void
    ) -> [PadItem] {
        var items = [PadItem("retry.again", enabled: canRetry, action: onRetry)]
        if showsRepair {
            items.append(PadItem("retry.repair", enabled: canRepairAndRetry, action: onRepairAndRetry))
        }
        items.append(PadItem("retry.garage", action: onGarage))
        return items
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
                    Text(headline.uppercased())
                        .font(Stage.label(11))
                        .kerning(Stage.Tracking.label(11))
                        .foregroundStyle(Stage.typeDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                if forfeited > 0 {
                    MoneySentence([
                        MoneyClause("The", forfeited, tint: Stage.danger,
                                    tail: " scrap from this match is forfeited.")
                    ])
                } else {
                    Text("Nothing was banked from this match.")
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.type)
                }
                Text("Nothing is lost but the scrap. The same opponent, the same arena, a different fight.")
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.typeDim)
                    .fixedSize(horizontal: false, vertical: true)
                if attempts >= 2, !matchTitle.isEmpty {
                    Text("That was the \(PostMatch.ordinal(attempts)) attempt at \(matchTitle).")
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, 10)

            Spacer(minLength: 0)
        }
    }

    /// "Clatterbox won at 2:14", or the honest line for a draw and for a fight given up.
    private var headline: String {
        if report.outcome == "forfeit" { return "\(report.botName) walked out" }
        if report.result == .draw { return "Neither machine won, after \(report.durationText)" }
        return "\(report.opponentName) won at \(report.durationText)"
    }

    // MARK: - The two answers

    private var answers: some View {
        VStack(alignment: .leading, spacing: 10) {
            StageButton("Retry", kind: .primary, enabled: canRetry, focusID: "retry.again", action: onRetry)

            if let retryBlock {
                Text(retryBlock)
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !repairBill.isPristine {
                StageButton(
                    "Repair and retry for \(repairBill.total)",
                    kind: .bare,
                    enabled: canRepairAndRetry,
                    focusID: "retry.repair",
                    action: onRepairAndRetry
                )
            }

            HStack {
                Spacer(minLength: 0)
                TextLink("Back to the garage", focusID: "retry.garage", action: onGarage)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)

            if !footnote.isEmpty {
            Text(footnote)
                .font(Stage.body(13))
                .foregroundStyle(Stage.textFaint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footnote: String {
        // The block sentence already says what the bill is and what is in the bank.
        if retryBlock != nil, !canAffordRepair { return "" }
        if repairBill.isPristine {
            return "\(report.botName) came out of it whole."
        }
        if !canAffordRepair {
            return "Repairs cost \(repairBill.total) and there is \(scrap) in the bank."
        }
        return "\(report.botName) goes back in with the damage it has."
    }
}
