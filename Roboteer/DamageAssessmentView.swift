//
//  DamageAssessmentView.swift
//  What the fight cost and what it paid. The repair bill part by part, the write off offer when
//  the bill is past seven tenths of the machine's value, the scrap and blueprints earned, and
//  whatever the rival has to say about it (docs/stage5-spec.md sections 2 and 6).
//
//  A pyrrhic win is meant to read as one, so the purse and the bill are printed side by side.
//

import SwiftUI

struct DamageAssessmentView: View {

    @Bindable var host: ArenaHost

    let settlement: CareerStore.Settlement
    let botName: String
    let opponentName: String
    let scrap: Int
    let tier: CareerTier
    /// G5 (wave G, brief v4 section 6): the bracket as it stands now, so the result of the tie just
    /// fought slides into it here, before the purse and the bill are settled. Nil outside a season.
    var bracket: CareerBracket? = nil
    var settledRound: Int = 0

    var onRepair: () -> Void
    var onWriteOff: () -> Void
    var onDone: () -> Void

    @State private var showBlueprint = false

    private var canAfford: Bool { scrap >= settlement.bill.total }

    var body: some View {
        ZStack {
            StageBackdrop(host: host, still: .empty, dim: 0.52)
            // The settlement has to be answered, so nothing here is a way into the turntable.
            StageTouchBlocker()

            VStack(alignment: .leading, spacing: 8) {
                header
                if let bracket {
                    BracketProgressStrip(bracket: bracket, settledRound: settledRound)
                }
                HStack(alignment: .top, spacing: 16) {
                    billPanel
                    ledger
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
            registerFocus()
            guard !settlement.newBlueprints.isEmpty else { return }
            withAnimation(.easeOut(duration: 0.45).delay(0.35)) { showBlueprint = true }
        }
    }

    // MARK: - Header

    /// The settlement's banner (design system section 5): WON in `win`, LOST in `danger`, on a
    /// lower third that comes in from the left, with what kind of win or loss it was beside it.
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            LowerThird(bar: settlement.didWin ? Stage.win : Stage.danger, entersFrom: .leading) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(settlement.didWin ? "WON" : "LOST")
                        .font(Stage.display(34))
                        .kerning(Stage.Tracking.display(34))
                        .foregroundStyle(settlement.didWin ? Stage.win : Stage.danger)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(outcomeTitle.uppercased())
                            .font(Stage.display(18))
                            .kerning(Stage.Tracking.display(18))
                            .foregroundStyle(Stage.type)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("\(botName.uppercased()) AGAINST \(opponentName.uppercased())")
                            .font(Stage.label(11))
                            .kerning(Stage.Tracking.label(11))
                            .foregroundStyle(Stage.typeDim)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            ScrapBadge(amount: scrap, size: 22, counts: true)
        }
    }

    private var outcomeTitle: String {
        if settlement.tookTheTier { return "\(tier.title) taken" }
        switch (settlement.didWin, settlement.outcome) {
        case (true, "ko"): return "Knockout win"
        case (true, "out_of_arena"): return "Thrown out, you win"
        case (true, "component_kill"): return "Core kill"
        case (true, _): return "Win on the judges"
        case (false, "ko"): return "Knocked out"
        case (false, "out_of_arena"): return "Out of the arena"
        case (false, "component_kill"): return "Core destroyed"
        default: return "Lost on the judges"
        }
    }

    // MARK: - The bill

    private var billPanel: some View {
        GlassPanel(padding: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    StageHeading("Damage assessment")
                    Spacer()
                    Text(settlement.bill.isPristine ? "NO DAMAGE" : "\(Int((settlement.bill.fractionOfValue * 100).rounded()))% OF VALUE")
                        .font(Stage.label(9, weight: .bold))
                        .kerning(1)
                        .foregroundStyle(settlement.bill.isWriteOff ? Stage.danger : Stage.textFaint)
                }

                if settlement.bill.isPristine {
                    Text("\(botName) came back without a mark on it.")
                        .font(Stage.body(12))
                        .foregroundStyle(Stage.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(settlement.bill.items) { item in
                                billRow(item)
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: 156)

                    HairRule()

                    HStack(alignment: .firstTextBaseline) {
                        Text("TOTAL")
                            .font(Stage.label(11, weight: .bold))
                            .kerning(1.2)
                            .foregroundStyle(Stage.text)
                        Spacer()
                        Text("\(settlement.bill.total)")
                            .font(Stage.numerals(19))
                            .foregroundStyle(settlement.bill.isWriteOff ? Stage.danger : Stage.text)
                        Text("of \(settlement.bill.buildValue)")
                            .font(Stage.label(11))
                            .foregroundStyle(Stage.textFaint)
                    }

                    if settlement.bill.isWriteOff {
                        Text("Repairing costs more than seven tenths of what the machine is worth. Stripping it returns \(settlement.bill.scrapForParts) scrap.")
                            .font(Stage.body(11))
                            .foregroundStyle(Stage.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !canAfford {
                        Text("You cannot afford the repair yet. The machine keeps its damage until you can.")
                            .font(Stage.body(11))
                            .foregroundStyle(Stage.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private func billRow(_ item: RepairBill.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.label.uppercased())
                .font(Stage.label(11))
                .foregroundStyle(Stage.textDim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Text("\(Int((item.lost * 100).rounded()))% gone")
                .font(Stage.body(10))
                .foregroundStyle(Stage.textFaint)
            Text("\(item.cost)")
                .font(Stage.numerals(13))
                .foregroundStyle(Stage.text)
                .frame(width: 46, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background {
            CutRect(6)
                .fill(Stage.type.opacity(0.03))
        }
    }

    // MARK: - What it paid

    /// The right column. The panels scroll and the answers are pinned under them, so a long bill,
    /// a long rival line or three blueprints can never push the buttons off the bottom of a 402 pt
    /// screen (which is exactly what happened the first time this was photographed).
    private var ledger: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ledgerPanels
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            answers
        }
        .frame(width: 264)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var ledgerPanels: some View {
        Group {
            GlassPanel(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    StageHeading("Earned")
                    CountingStat(label: "Purse", value: settlement.purse)
                    CountingStat(label: "Salvage", value: settlement.scrapEarned)
                    if settlement.tookTheTier {
                        StageStat(label: "Garage slots", value: "\(settlement.newCapacity)")
                    }
                    if let next = settlement.advancedTo {
                        Text("The \(next.title) circuit is open.")
                            .font(Stage.body(11))
                            .foregroundStyle(Stage.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // The win stands and the circuit does not move on: say so plainly, once, with
                    // no buy button on this screen. The offer comes after, on its own.
                    if settlement.hitTheWall, !settlement.wallSentence.isEmpty {
                        Text(settlement.wallSentence)
                            .font(Stage.body(11))
                            .foregroundStyle(Stage.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(settlement.newBlueprints, id: \.self) { id in
                        blueprintFlourish(id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !settlement.rivalLine.isEmpty {
                GlassPanel(padding: 12) {
                    Text(settlement.rivalLine)
                        .font(Stage.body(12))
                        .italic()
                        .foregroundStyle(Stage.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

        }
    }

    @ViewBuilder
    private var answers: some View {
        VStack(alignment: .leading, spacing: 6) {
            if settlement.bill.isPristine {
                StageButton("Back to the garage", kind: .primary, focusID: "done", action: onDone)
            } else {
                StageButton("Repair for \(settlement.bill.total)", kind: .primary, enabled: canAfford, focusID: "repair", action: onRepair)
                if settlement.bill.isWriteOff {
                    StageButton("Write off for \(settlement.bill.scrapForParts)", kind: .danger, focusID: "writeoff", action: onWriteOff)
                }
                StageButton("Leave it for now", kind: .quiet, focusID: "done", action: onDone)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func registerFocus() {
        var items: [PadItem] = []
        if !settlement.bill.isPristine {
            items.append(PadItem("repair", enabled: canAfford) { onRepair() })
            if settlement.bill.isWriteOff {
                items.append(PadItem("writeoff") { onWriteOff() })
            }
        }
        items.append(PadItem("done") { onDone() })
        PadFocus.shared.set(items, back: { onDone() })
    }

    /// "New blueprint: Axe", arriving a beat after the screen does.
    private func blueprintFlourish(_ id: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Stage.gold)
            Text("New blueprint: \(CareerEngine.partName(id))")
                .font(Stage.label(12, weight: .bold))
                .foregroundStyle(Stage.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            CutRect(8)
                .fill(Stage.scrap.opacity(0.12))
        }
        .overlay {
            CutRect(8)
                .strokeBorder(Stage.scrap.opacity(0.5), lineWidth: 1)
        }
        .opacity(showBlueprint ? 1 : 0)
        .scaleEffect(showBlueprint ? 1 : 0.94, anchor: .leading)
    }
}

// MARK: - A number that is won rather than printed

/// A stat strip whose number counts up over 0.4 s (design system section 3). The settlement is the
/// one screen where the money arriving is the point, so the purse and the salvage use it and every
/// other row on the screen prints.
struct CountingStat: View {
    let label: String
    let value: Int
    var tint: Color = Stage.scrap

    var body: some View {
        LowerThird(bar: Stage.lineDim, fill: Stage.type.opacity(0.04), padding: EdgeInsets(top: 3, leading: 4, bottom: 3, trailing: 8), leanInset: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label.uppercased())
                    .font(Stage.label(11))
                    .kerning(Stage.Tracking.label(11))
                    .foregroundStyle(Stage.textFaint)
                Spacer(minLength: 4)
                CountingNumber(value: value, font: Stage.numerals(15), tint: tint)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }
}
