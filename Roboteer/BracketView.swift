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
    /// Wave C: the match on duty (for the opponent across the floor, the arena line and FIGHT),
    /// the machine going out, and whether it can go.
    var next: NextMatch? = nil
    var bot: BotBuild? = nil
    var canFight: Bool = false
    var onFight: (() -> Void)? = nil
    /// Replay a match already won. Only offered once the campaign is finished, or once the next
    /// Series is behind the full game wall (brief v5 section 9.1).
    var onReplay: (Int, Int) -> Void = { _, _ in }
    var onUnlock: () -> Void = {}
    var onBack: () -> Void

    @State private var keepOut = LeaderKeepOut()

    private var canReplay: Bool { ProgressionEngine.replaysAvailable(state: state, gates: gates) }

    /// Direction A's Series board (docs/look/menus-blueprint.html): the two machines face off on
    /// the stage with a leader to each, the whole campaign is one schedule plate across the foot,
    /// and FIGHT sits under it with the match's one sentence.
    var body: some View {
        ZStack {
            StageBackdrop(host: host, still: .withBot, dim: 0, shade: .bottom)

            GeometryReader { proxy in
                let compact = proxy.size.height < 400
                ZStack(alignment: .topLeading) {
                    StageLeaderLayer(anchors: host.stageAnchors, screen: "board",
                                     leaders: boardLeaders, keepOut: keepOut)
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        Spacer(minLength: 8)
                        schedule(compact: compact)
                            .leaderKeepOut(keepOut, "schedule")
                        HStack(alignment: .center, spacing: 12) {
                            footLine
                            Spacer(minLength: 8)
                            if let onFight, next != nil {
                                StageButton("Fight", kind: .primary, enabled: canFight, focusID: "board.fight", action: onFight)
                                    .frame(width: 150)
                                    .leaderKeepOut(keepOut, "fight")
                            }
                        }
                        .padding(.top, 6)
                    }
                    .padding(.top, compact ? 12 : 16)
                    .padding(.bottom, compact ? 2 : 8)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear { registerFocus() }
        .onChange(of: canFight) { _, _ in registerFocus() }
    }

    private func registerFocus() {
        var items: [PadItem] = []
        if let onFight, next != nil {
            items.append(PadItem("board.fight", enabled: canFight) { onFight() })
        }
        if gates.firstLockedTier != nil {
            items.append(PadItem("unlock") { onUnlock() })
        }
        PadFocus.shared.set(items, back: { onBack() })
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            BackChevron(action: onBack)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Blueprint.display(28))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                (Text("Level ") + Text("\(state.level)").font(Blueprint.mono(13.5)).foregroundStyle(Color.white)
                 + Text(". Record ") + Text("\(state.wins)").font(Blueprint.mono(13.5)).foregroundStyle(Color.white)
                 + Text(" of ") + Text("\(state.fightsPlayed)").font(Blueprint.mono(13.5)).foregroundStyle(Color.white)
                 + Text("."))
                    .font(Blueprint.body(13.5))
                    .foregroundStyle(Blueprint.dim)
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            }
            .padding(.top, -2)
            Spacer(minLength: 8)
            if gates.firstLockedTier != nil {
                TextLink("Unlock the full game", tint: Color.white, focusID: "unlock", action: onUnlock)
            }
        }
        .leaderKeepOut(keepOut, "header")
    }

    /// "Series 2: Regional", the Series the board is standing in.
    private var title: String {
        let index = min(state.seriesIndex, CareerTier.allCases.count - 1)
        return "Series \(index + 1): \(CareerTier.allCases[index].title)"
    }

    // MARK: - The schedule

    private static let nameWidth: CGFloat = 168

    private func schedule(compact: Bool) -> some View {
        let rowHeight: CGFloat = compact ? 20 : 22
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("Series").frame(width: Self.nameWidth, alignment: .leading).padding(.leading, 8)
                ForEach(0..<SeriesProgress.matchesPerSeries, id: \.self) { match in
                    Text(match == SeriesProgress.matchesPerSeries - 1 ? "Final" : "Match \(match + 1)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 8)
                }
            }
            .font(Blueprint.ui(11.5))
            .foregroundStyle(Blueprint.dim)
            .frame(height: 20)
            ForEach(0..<SeriesProgress.seriesCount, id: \.self) { index in
                row(index, height: rowHeight)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .blueprintPlate()
    }

    private func row(_ seriesIndex: Int, height: CGFloat) -> some View {
        let tier = CareerTier.allCases[seriesIndex]
        let locked = !gates.tierAvailable(tier)
        let slots = ProgressionEngine.seriesSlots(state: state, seriesIndex: seriesIndex, logs: logs)
        return HStack(spacing: 4) {
            HStack(spacing: 6) {
                Text("Series \(seriesIndex + 1)").font(Blueprint.ui(12.5)).foregroundStyle(Color.white)
                Text(tier.title).font(Blueprint.body(13)).foregroundStyle(Blueprint.dim)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.leading, 8)
            .frame(width: Self.nameWidth, alignment: .leading)
            if locked {
                HStack {
                    Text(gates.lockedReasonIfLocked(.tier(tier)) == nil ? "Locked" : "Needs the full game")
                        .font(Blueprint.ui(12)).foregroundStyle(Blueprint.dim)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { BlueprintHatch() }
            } else {
                ForEach(slots) { slot in
                    cell(slot, seriesIndex: seriesIndex)
                }
            }
        }
        .frame(height: height)
    }

    private func cell(_ slot: SeriesMatchSlot, seriesIndex: Int) -> some View {
        let isNext = slot.state == .next
        let replay = slot.state == .replayable && canReplay
        let word: String = {
            switch slot.state {
            case .won: return "Won"
            case .replayable: return canReplay ? "Replay" : "Won"
            case .next: return "Next"
            case .locked: return slot.isFinal ? "Final" : ""
            }
        }()
        return HStack(spacing: 4) {
            Text(slot.opponentName)
                .font(Blueprint.ui(13))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 2)
            Text(word).font(Blueprint.ui(11))
                .foregroundStyle(isNext ? Blueprint.primaryInk : Blueprint.dim)
        }
        .foregroundStyle(isNext ? Blueprint.primaryInk : (slot.state == .locked ? Blueprint.dim : Color.white))
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Rectangle().fill(isNext ? Blueprint.primary : Color.white.opacity(0.07)) }
        .contentShape(Rectangle())
        .onTapGesture { if replay { onReplay(seriesIndex, slot.index) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(replay ? .isButton : [])
    }

    /// "The Grinder. Cinder on duty. A win pays up to 450 scrap and 450 points."
    @ViewBuilder
    private var footLine: some View {
        if let next {
            let rules = next.scrapRules
            let most = rules.base + rules.damageFull + rules.survivor + rules.flawless
            MoneySentence([
                MoneyClause("\(next.arenaName). \(next.houseBotName.asName) on duty. A win pays up to", most,
                            tint: Color.white, tail: " scrap and"),
                MoneyClause("", next.winPoints, tint: Color.white, tail: " points.")
            ], size: 13.5, tint: Blueprint.dim)
            .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            .lineLimit(2)
        } else {
            Text(state.campaignComplete ? "Every Series is won. Replay any match you have won for half."
                                        : "Series \(state.seriesIndex + 1), match \(min(state.matchIndex, 3) + 1) is next.")
                .font(Blueprint.body(13.5))
                .foregroundStyle(Blueprint.dim)
        }
    }

    // MARK: - The leaders

    /// The player's machine on the left and the opponent across the floor.
    private var boardLeaders: [Leader] {
        var out: [Leader] = []
        if let next {
            let spec = next.opponent.spec
            out.append(Leader(id: "opponent", target: .point("opponent"), title: next.opponent.name,
                              value: BuildRules.kilograms(BuildRules.totalWeight(spec)),
                              sub: "\(next.opponent.roboteer). \(next.partsLine)", dx: 80, dy: -58))
        }
        if let bot {
            out.append(Leader(id: "player", target: .point("top"), title: bot.name,
                              value: BuildRules.kilograms(bot.totalWeight), dx: -50, dy: -60))
        }
        return out
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
