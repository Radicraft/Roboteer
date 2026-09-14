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

    var onRepair: () -> Void
    var onWriteOff: () -> Void
    var onDone: () -> Void

    @State private var showBlueprint = false

    private var canAfford: Bool { scrap >= settlement.bill.total }

    var body: some View {
        ZStack {
            StageBackdrop(host: host, still: .empty, dim: 0.52)

            VStack(alignment: .leading, spacing: 10) {
                header
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(outcomeTitle.uppercased())
                .font(Stage.display(30, weight: .black))
                .kerning(1.4)
                .foregroundStyle(Stage.text)
            Text("\(botName.uppercased()) AGAINST \(opponentName.uppercased())")
                .font(Stage.label(12))
                .foregroundStyle(Stage.textDim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            ScrapBadge(amount: scrap, size: 20)
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
                    .frame(maxHeight: 172)

                    Divider().overlay(Stage.edge)

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
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.03))
        }
    }

    // MARK: - What it paid

    private var ledger: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassPanel(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    StageHeading("Earned")
                    StageStat(label: "Purse", value: "\(settlement.purse)", tint: Stage.gold)
                    StageStat(label: "Salvage", value: "\(settlement.scrapEarned)", tint: Stage.gold)
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

            Spacer(minLength: 0)

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
        .frame(width: 264)
        .frame(maxHeight: .infinity, alignment: .top)
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
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Stage.gold.opacity(0.14))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Stage.gold.opacity(0.5), lineWidth: 1)
        }
        .opacity(showBlueprint ? 1 : 0)
        .scaleEffect(showBlueprint ? 1 : 0.94, anchor: .leading)
    }
}
