//
//  BracketView.swift
//  The tournament board: eight entrants, three rounds, built entirely from `CareerBracket` so it
//  is right whatever the draw did. The player's machine is the lit slot; everything else is glass.
//
//  Layout reference only: Art/direction/bracket-screen.png. The look is the dark stage style of
//  docs/stage2-art-direction.md ("Owner decision 2026-09-13: menus are AAA cinematic").
//

import SwiftUI

struct BracketView: View {

    @Bindable var host: ArenaHost
    let bracket: CareerBracket
    let tier: CareerTier
    var onScout: () -> Void
    var onBack: () -> Void

    var body: some View {
        ZStack {
            StageBackdrop(host: host, still: .empty, dim: 0.5)

            VStack(alignment: .leading, spacing: 10) {
                header
                board
                footer
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            PadFocus.shared.set(
                [PadItem("scout", enabled: bracket.playerMatch != nil) { onScout() }],
                back: { onBack() }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            StageButton("Back", kind: .quiet, action: onBack)
                .frame(width: 96)
            Text("\(tier.title.uppercased()) BRACKET")
                .font(Stage.display(24))
                .kerning(1.6)
                .foregroundStyle(Stage.text)
            Spacer(minLength: 8)
            Text(statusLine)
                .font(Stage.label(12))
                .foregroundStyle(Stage.textDim)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var statusLine: String {
        if let match = bracket.playerMatch {
            return "\(CareerBracket.roundTitle(match.round, of: CareerBracket.rounds)). Eight in, one out."
        }
        if bracket.playerWonTier { return "You took the \(tier.title)." }
        return "Knocked out. The board played itself out."
    }

    // MARK: - The board

    private var board: some View {
        ScrollView(.vertical) {
            columns
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var columns: some View {
        HStack(alignment: .top, spacing: 10) {
            column(round: 0, title: "Quarter-finals")
            column(round: 1, title: "Semi-finals")
            column(round: 2, title: "Final")
            championColumn
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func column(round: Int, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            StageHeading(title)
            if round > 0 {
                // Later rounds sit lower, so the three columns read as a tree.
                Color.clear.frame(width: 1, height: CGFloat(round) * 26)
            }
            VStack(spacing: 8) {
                ForEach(bracket.matches(inRound: round), id: \.slot) { match in
                    tie(match)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tie(_ match: CareerMatch) -> some View {
        VStack(spacing: 2) {
            slot(match.a, winner: match.winner)
            slot(match.b, winner: match.winner)
            if !match.note.isEmpty {
                Text(match.note.uppercased())
                    .font(Stage.label(8, weight: .bold))
                    .kerning(0.8)
                    .foregroundStyle(Stage.textFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 2)
            }
        }
        .padding(6)
        .background {
            CutRect(9)
                .fill(Stage.type.opacity(match.has(bracket.playerIndex) ? 0.07 : 0.025))
        }
        .overlay {
            CutRect(9)
                .strokeBorder(match.has(bracket.playerIndex) ? Stage.edgeBright : Stage.edge, lineWidth: 1)
        }
    }

    private func slot(_ index: Int?, winner: Int?) -> some View {
        let entrant = bracket.entrant(index)
        let isPlayer = index != nil && index == bracket.playerIndex
        let isWinner = winner != nil && winner == index
        let isBeaten = winner != nil && !isWinner
        return HStack(spacing: 6) {
            LiverySwatch(hex: entrant?.liveryHex ?? "#2a2d33", size: 12, selected: isPlayer)
            Text((entrant?.name ?? "To be decided").uppercased())
                .font(Stage.display(14))
                .kerning(Stage.Tracking.display(14))
                .foregroundStyle(entrant == nil ? Stage.textFaint : (isBeaten ? Stage.textFaint : Stage.type))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .strikethrough(isBeaten, color: Stage.textFaint)
            if let entrant, !entrant.roboteer.isEmpty {
                Text(entrant.roboteer.uppercased())
                    .font(Stage.label(11))
                    .kerning(Stage.Tracking.label(11))
                    .foregroundStyle(Stage.textFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 2)
            if isWinner {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Stage.line)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            CutRect(6)
                .fill(isPlayer ? Stage.type.opacity(0.14) : Stage.type.opacity(0.03))
        }
    }

    private var championColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            StageHeading("Champion")
            GlassPanel(padding: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    if let final = bracket.matches.last, let winner = final.winner,
                       let entrant = bracket.entrant(winner) {
                        HStack(spacing: 6) {
                            LiverySwatch(hex: entrant.liveryHex, size: 16, selected: winner == bracket.playerIndex)
                            Text(entrant.name.uppercased())
                                .font(Stage.display(15))
                                .kerning(0.8)
                                .foregroundStyle(Stage.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        Text(entrant.roboteer)
                            .font(Stage.body(10))
                            .foregroundStyle(Stage.textDim)
                        if winner == bracket.playerIndex {
                            Text("TIER TAKEN")
                                .font(Stage.label(9, weight: .bold))
                                .kerning(1.2)
                                .foregroundStyle(Stage.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Stage.win, in: CutRect(6))
                        }
                    } else {
                        Text("Still to be decided.")
                            .font(Stage.body(11))
                            .foregroundStyle(Stage.textFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 150, alignment: .leading)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if let opponent = bracket.playerNextOpponent {
                Text("NEXT: \(opponent.name.uppercased()), \(opponent.roboteer.uppercased())")
                    .font(Stage.label(12))
                    .foregroundStyle(Stage.textDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            StageButton("Scouting report", kind: .primary, enabled: bracket.playerMatch != nil, focusID: "scout", action: onScout)
                .frame(width: 230)
        }
    }
}

// MARK: - The board, small enough to live under something else (G5, wave G)

/// The bracket of eight as it appears in the MIDDLE of the season screen (brief v4 section 6):
/// three columns, the rounds named, the player's slot lit, results filled in as the season goes.
///
/// It is the same `CareerBracket` and the same reading as `BracketView`, drawn to fit a 430 pt
/// column beside the live machine rather than a whole screen. Tapping it opens the full board.
struct CompactBracket: View {

    let bracket: CareerBracket
    /// The tie that has just been settled, which arrives lit and then settles down with the rest.
    var highlightRound: Int? = nil
    var onOpen: (() -> Void)? = nil

    @State private var arrived = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                StageHeading("The bracket")
                Spacer(minLength: 4)
                if onOpen != nil {
                    Text("FULL BOARD")
                        .font(Stage.label(9, weight: .bold))
                        .kerning(1)
                        .foregroundStyle(Stage.textFaint)
                }
            }
            HStack(alignment: .top, spacing: 6) {
                column(round: 0, title: "Quarter-final")
                column(round: 1, title: "Semi-final")
                column(round: 2, title: "Final")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onOpen?() }
        .onAppear {
            guard highlightRound != nil, !arrived else { return }
            withAnimation(.easeOut(duration: 0.45).delay(0.2)) { arrived = true }
        }
    }

    private func column(round: Int, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(Stage.label(8, weight: .bold))
                .kerning(0.9)
                .foregroundStyle(Stage.textFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if round > 0 {
                // Later rounds sit a little lower, so the three columns read as a tree. Fixed
                // padding rather than `maxHeight: .infinity`, which made the panel as tall as the
                // space it was given and pushed the next-fight card off the season screen.
                Color.clear.frame(width: 1, height: CGFloat(round) * 18)
            }
            VStack(spacing: 4) {
                ForEach(bracket.matches(inRound: round), id: \.slot) { match in
                    tie(match, round: round)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tie(_ match: CareerMatch, round: Int) -> some View {
        let mine = match.has(bracket.playerIndex)
        let lit = mine && highlightRound == round
        return VStack(spacing: 1) {
            slot(match.a, winner: match.winner)
            slot(match.b, winner: match.winner)
        }
        .padding(3)
        .background {
            CutRect(6)
                .fill(Stage.type.opacity(mine ? 0.07 : 0.02))
        }
        .overlay {
            CutRect(6)
                .strokeBorder(mine ? Stage.edgeBright : Stage.edge, lineWidth: 1)
        }
        // The result sliding into the board: the tie just settled comes in from the right and
        // brightens, once, on the way back from the arena.
        .offset(x: lit && !arrived ? 14 : 0)
        .opacity(lit && !arrived ? 0 : 1)
    }

    private func slot(_ index: Int?, winner: Int?) -> some View {
        let entrant = bracket.entrant(index)
        let isPlayer = index != nil && index == bracket.playerIndex
        let isWinner = winner != nil && winner == index
        let isBeaten = winner != nil && !isWinner
        return HStack(spacing: 4) {
            LiverySwatch(hex: entrant?.liveryHex ?? "#2a2d33", size: 7, selected: isPlayer)
            Text((entrant?.name ?? "To be decided").uppercased())
                .font(Stage.display(9))
                .kerning(0.4)
                .foregroundStyle(entrant == nil ? Stage.textFaint : (isBeaten ? Stage.textFaint : Stage.text))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .strikethrough(isBeaten, color: Stage.textFaint)
            Spacer(minLength: 1)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background {
            CutRect(4)
                .fill(isPlayer ? Stage.type.opacity(0.16) : Color.clear)
        }
    }
}

/// The player's own path through the season as one row, for the settlement screen: three round
/// chips, filled in as the season goes, with the tie that has just been fought sliding in.
///
/// This is "the result slides into the bracket" of brief v4 section 6, in the space a settlement
/// screen can actually spare.
struct BracketProgressStrip: View {

    let bracket: CareerBracket
    /// The round just fought.
    let settledRound: Int

    @State private var arrived = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<CareerBracket.rounds, id: \.self) { round in
                chip(round)
            }
            Spacer(minLength: 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.25)) { arrived = true }
        }
    }

    private func chip(_ round: Int) -> some View {
        let match = bracket.matches(inRound: round).first { $0.has(bracket.playerIndex) }
        let settled = match?.isSettled ?? false
        let won = settled && match?.winner == bracket.playerIndex
        let isNew = round == settledRound
        let opponent = match.flatMap { $0.opponent(of: bracket.playerIndex) }.flatMap { bracket.entrant($0) }

        return VStack(alignment: .leading, spacing: 1) {
            Text(CareerBracket.roundTitle(round, of: CareerBracket.rounds).uppercased())
                .font(Stage.label(8, weight: .bold))
                .kerning(0.9)
                .foregroundStyle(Stage.textFaint)
            Text(line(settled: settled, won: won, opponent: opponent))
                .font(Stage.display(11))
                .kerning(0.4)
                .foregroundStyle(settled ? (won ? Stage.text : Stage.textFaint) : Stage.textFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background {
            CutRect(7)
                .fill(Stage.type.opacity(isNew ? 0.10 : 0.03))
        }
        .overlay {
            CutRect(7)
                .strokeBorder(isNew ? Stage.edgeBright : Stage.edge, lineWidth: 1)
        }
        .offset(x: isNew && !arrived ? 20 : 0)
        .opacity(isNew && !arrived ? 0 : 1)
    }

    private func line(settled: Bool, won: Bool, opponent: CareerEntrant?) -> String {
        guard let opponent else { return settled ? "Not reached" : "To be drawn" }
        guard settled else { return opponent.name.uppercased() }
        return "\(won ? "BEAT" : "LOST TO") \(opponent.name.uppercased())"
    }
}
