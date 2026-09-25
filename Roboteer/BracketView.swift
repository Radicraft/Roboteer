//
//  BracketView.swift
//  The campaign board: five Series, four matches each, the whole game on one screen with no
//  scrolling (option C1 of docs/look/series-options.html). A Series is a row, a match is a cell
//  with the opponent and what happened, and the fourth column is the Series final, said once in
//  the header rather than on every cell.
//
//  Wave P (brief v5): this file used to draw the eight machine bracket. There is no bracket now.
//  What is left of the old screen is the idea: the whole campaign, visible, one tap from the
//  Series screen. `SeriesStrip` at the foot of this file is the four slot version that lives
//  under the next-match card.
//
//  Everything on both is read from `ProgressionEngine.seriesSlots`, so the strip and the board
//  cannot disagree about what has been won.
//

import SwiftUI

struct CampaignBoardView: View {

    @Bindable var host: ArenaHost
    let state: CareerState
    /// The career's fight log, so a won cell can say how it was won.
    var logs: [FightLog] = []
    var gates: Gates = Gates.snapshot
    /// Replay a match already won. Only offered once the campaign is finished, or once the next
    /// Series is behind the full game wall (brief v5 section 9.1).
    var onReplay: (Int, Int) -> Void = { _, _ in }
    var onUnlock: () -> Void = {}
    var onBack: () -> Void

    private var canReplay: Bool { ProgressionEngine.replaysAvailable(state: state, gates: gates) }

    var body: some View {
        ZStack {
            StageBackdrop(host: host, still: .empty, dim: 0.5)

            VStack(alignment: .leading, spacing: 8) {
                header
                HairRule()
                board
                Spacer(minLength: 0)
                Ticker(lines: tickerLines, textInset: 28)
                    .padding(.horizontal, -28)
                    .ignoresSafeArea(edges: .horizontal)
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear { registerFocus() }
    }

    private func registerFocus() {
        var items: [PadItem] = []
        if gates.firstLockedTier != nil {
            items.append(PadItem("unlock") { onUnlock() })
        }
        PadFocus.shared.set(items, back: { onBack() })
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            BackChevron(action: onBack)
            Text("THE CAMPAIGN")
                .font(Stage.display(22))
                .kerning(Stage.Tracking.display(22))
                .foregroundStyle(Stage.text)
            Text(subtitle)
                .font(Stage.body(13))
                .foregroundStyle(Stage.typeDim)
                .lineLimit(1)
                .minimumScaleFactor(BroadcastType.floorScale(.body, size: 13, wanted: 0.7))
            Spacer(minLength: 8)
            if gates.firstLockedTier != nil {
                TextLink("Unlock the full game", tint: Stage.line, focusID: "unlock", action: onUnlock)
            }
        }
    }

    private var subtitle: String {
        "Five Series, four matches each. Level \(state.level) of \(ProgressionEngine.progression.levelCap)."
    }

    // MARK: - The board

    private var board: some View {
        VStack(alignment: .leading, spacing: 5) {
            headerRow
            ForEach(0..<SeriesProgress.seriesCount, id: \.self) { index in
                row(index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let nameWidth: CGFloat = 132

    private var headerRow: some View {
        HStack(alignment: .bottom, spacing: 5) {
            Color.clear.frame(width: Self.nameWidth, height: 1)
            ForEach(0..<SeriesProgress.matchesPerSeries, id: \.self) { match in
                Text(match == SeriesProgress.matchesPerSeries - 1 ? "SERIES FINAL" : "MATCH \(match + 1)")
                    .font(Stage.label(11))
                    .kerning(Stage.Tracking.label(11))
                    .foregroundStyle(Stage.typeDim)
                    .lineLimit(1)
                    .minimumScaleFactor(BroadcastType.floorScale(.label, size: 11, wanted: 0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 6)
            }
        }
    }

    private func row(_ seriesIndex: Int) -> some View {
        let tier = CareerTier.allCases[seriesIndex]
        let locked = !gates.tierAvailable(tier)
        let slots = ProgressionEngine.seriesSlots(state: state, seriesIndex: seriesIndex, logs: logs)
        return HStack(alignment: .top, spacing: 5) {
            HStack(alignment: .center, spacing: 7) {
                // The Series mark: the manifest's badge for this Series (design system section 6,
                // `tier_<id>.svg`), drawn rather than boxed, in the row's own colour.
                GlyphMark(art: BroadcastGlyph.series(tier.rawValue), size: 26,
                          tint: locked ? Stage.textFaint : Stage.line)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Stage.textFaint)
                        }
                        Text("SERIES \(seriesIndex + 1)")
                            .font(Stage.display(13))
                            .kerning(Stage.Tracking.display(13))
                            .foregroundStyle(locked ? Stage.textFaint : Stage.type)
                    }
                    Text(tier.title)
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.textFaint)
                        .lineLimit(1)
                        .minimumScaleFactor(BroadcastType.floorScale(.body, size: 13, wanted: 0.7))
                }
            }
            .frame(width: Self.nameWidth, alignment: .leading)

            ForEach(slots) { slot in
                cell(slot, seriesIndex: seriesIndex, locked: locked)
            }
        }
    }

    @ViewBuilder
    private func cell(_ slot: SeriesMatchSlot, seriesIndex: Int, locked: Bool) -> some View {
        if locked {
            // The reason is said once for the whole Series, on its first cell, rather than four
            // times across the row.
            SlotCell(
                head: slot.index == 0 ? "Locked" : " ",
                note: slot.index == 0 ? "needs the full game" : "",
                state: .locked
            )
        } else {
            SlotCell(
                head: slot.opponentName,
                note: note(slot),
                state: cellState(slot),
                action: slot.state == .replayable && canReplay
                    ? { onReplay(seriesIndex, slot.index) }
                    : nil
            )
        }
    }

    private func cellState(_ slot: SeriesMatchSlot) -> SlotCell.State {
        switch slot.state {
        case .won: return .won
        case .next: return .next
        case .replayable: return .replay
        case .locked: return .waiting
        }
    }

    private func note(_ slot: SeriesMatchSlot) -> String {
        switch slot.state {
        case .won: return slot.note.isEmpty ? "won" : slot.note.lowercasedFirst
        case .replayable: return slot.note.isEmpty ? "won. Replay it" : "\(slot.note.lowercasedFirst). Replay it"
        case .next: return "next"
        case .locked: return "to come"
        }
    }

    private var tickerLines: [String] {
        var lines: [String] = []
        if state.campaignComplete {
            lines.append("EVERY SERIES WON. ANY MATCH CAN BE REPLAYED FOR HALF.")
        } else {
            lines.append("SERIES \(state.seriesIndex + 1), MATCH \(min(state.matchIndex, 3) + 1) IS NEXT.")
        }
        lines.append("LEVEL \(state.level). \(state.scrap) SCRAP IN HAND.")
        return lines
    }
}

// MARK: - The Series as a strip

/// The Series under the next-match card: the four matches with the result written under each one
/// and the match on duty lit, plus one cell for what comes after this Series. Tapping it opens the
/// campaign board; tapping a won match while replays are open starts a replay (design system
/// section 8: never five boxes).
struct SeriesStrip: View {

    let slots: [SeriesMatchSlot]
    let seriesIndex: Int
    /// True when the Series after this one is behind the full game wall.
    var nextSeriesLocked: Bool = false
    var onOpen: (() -> Void)? = nil
    /// Nil until replays are open (brief v5 section 9.1).
    var onReplay: ((Int) -> Void)? = nil
    /// The strip is a tap target, so a pad has to be able to land on it and see that it has.
    var focusID: String? = "board"

    private var focused: Bool {
        guard let focusID else { return false }
        return PadFocus.shared.isFocused(focusID)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(slots) { slot in
                SlotCell(
                    head: "\(slot.index + 1) · \(slot.opponentName)",
                    note: note(slot),
                    state: state(slot),
                    action: action(slot)
                )
            }
            afterCell
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(2)
        .background {
            Rectangle().fill(Stage.selectedFill).opacity(focused ? 1 : 0).allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen?() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("This Series so far. Opens the campaign board.")
    }

    /// The sixth word on the strip: what happens after this Series.
    private var afterCell: some View {
        let last = seriesIndex >= SeriesProgress.seriesCount - 1
        return SlotCell(
            head: last ? "The end" : "Series \(seriesIndex + 2)",
            note: last ? "the last Series" : (nextSeriesLocked ? "full game" : "after the final"),
            state: nextSeriesLocked || last ? .locked : .waiting,
            action: onOpen
        )
    }

    private func state(_ slot: SeriesMatchSlot) -> SlotCell.State {
        switch slot.state {
        case .won: return .won
        case .next: return .next
        case .replayable: return .replay
        case .locked: return .waiting
        }
    }

    private func note(_ slot: SeriesMatchSlot) -> String {
        switch slot.state {
        case .won: return slot.note.isEmpty ? "won" : slot.note.lowercasedFirst
        case .replayable: return "replay it"
        case .next: return slot.isFinal ? "the final, next" : "next"
        case .locked: return slot.isFinal ? "the final" : "to come"
        }
    }

    private func action(_ slot: SeriesMatchSlot) -> (() -> Void)? {
        guard slot.state == .replayable, let onReplay else { return nil }
        return { onReplay(slot.index) }
    }
}

extension String {
    /// "Knockout at 34 s" in the middle of a sentence. The catalogue's own words, turned down.
    var lowercasedFirst: String {
        guard let first = first else { return self }
        return first.lowercased() + dropFirst()
    }
}
