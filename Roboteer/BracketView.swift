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
            return "\(CareerBracket.roundName(match.round, of: CareerBracket.rounds).capitalizedFirst). Eight in, one out."
        }
        if bracket.playerWonTier { return "You took the \(tier.title)." }
        return "Knocked out. The board played itself out."
    }

    // MARK: - The board

    private var board: some View {
        HStack(alignment: .top, spacing: 10) {
            column(round: 0, title: "Quarter finals")
            column(round: 1, title: "Semi finals")
            column(round: 2, title: "Final")
            championColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func column(round: Int, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            StageHeading(title)
            VStack(spacing: 8) {
                ForEach(bracket.matches(inRound: round), id: \.slot) { match in
                    tie(match)
                }
            }
            .frame(maxHeight: .infinity, alignment: roundAlignment(round))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Later rounds sit further down so the tree reads as a tree rather than three lists.
    private func roundAlignment(_ round: Int) -> Alignment {
        round == 0 ? .top : .center
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
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(match.has(bracket.playerIndex) ? 0.07 : 0.025))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
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
            VStack(alignment: .leading, spacing: 0) {
                Text((entrant?.name ?? "To be decided").uppercased())
                    .font(Stage.display(12))
                    .kerning(0.6)
                    .foregroundStyle(entrant == nil ? Stage.textFaint : (isBeaten ? Stage.textFaint : Stage.text))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .strikethrough(isBeaten, color: Stage.textFaint)
                if let entrant, !entrant.roboteer.isEmpty {
                    Text(entrant.roboteer)
                        .font(Stage.body(9))
                        .foregroundStyle(Stage.textFaint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 2)
            if isWinner {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Stage.text)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isPlayer ? Color.white.opacity(0.14) : Color.white.opacity(0.03))
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
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Stage.gold, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
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
