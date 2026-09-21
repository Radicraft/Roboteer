//
//  ShopView.swift
//  The shop (brief v5 sections 3, 7 and 9.4), drawn as option H1 of
//  docs/look/series-options.html: one list the whole width of the screen, grouped under kind
//  headings, with the five kinds as a line of words at the top that jump the list rather than tabs.
//
//  A row is the part's name, its weight, what the catalogue knows about it, the price in the scrap
//  colour and ONE word for what you can do: BUY, OWNED, the Level it needs, or the price in the
//  danger colour when it cannot be afforded yet. Scrap and Level are one sentence at the top, not
//  two bugs (design system section 8).
//
//  Nothing here decides anything: `ProgressionEngine.shopEntries` prices and gates every row and
//  `CareerStore.buy` takes the money, so a row and a purchase can never disagree.
//

import SwiftUI
import SwiftData

struct ShopView: View {

    @Bindable var host: ArenaHost
    @Bindable var state: CareerState
    var onClose: () -> Void

    @Environment(\.modelContext) private var context

    /// The part the player just bought, so the row can say so for a moment.
    @State private var justBought: String = ""
    /// The heading the category words jump to: a category's raw value, or "coming".
    @State private var jump: String?

    private var gates: Gates { Gates.snapshot }
    private var entries: [ShopEntry] { ProgressionEngine.shopEntries(state: state, gates: gates) }

    private static let gutter: CGFloat = 26

    var body: some View {
        ZStack {
            StageBackdrop(host: host, still: .empty, dim: 0.52)

            VStack(alignment: .leading, spacing: 7) {
                header
                HairRule()
                categoryLine
                list
                Ticker(lines: tickerLines, textInset: Self.gutter)
                    .padding(.horizontal, -Self.gutter)
                    .ignoresSafeArea(edges: .horizontal)
            }
            .padding(.horizontal, Self.gutter)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            PadFocus.shared.set([], back: { onClose() })
            // QA (docs/qa-launch-flags.md): `-shopAt weapon` opens the shop already scrolled to a
            // group, so every part of a 45 row list can be photographed without a thumb.
            if let name = ArenaHost.launchArgument("-shopAt") { jump = name }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            BackChevron(action: onClose)
            Text("SHOP")
                .font(Stage.display(22))
                .kerning(Stage.Tracking.display(22))
                .foregroundStyle(Stage.text)
            standing
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
    }

    /// "Level 12. 900 scrap in hand. A part you have bought is yours for good."
    private var standing: Text {
        var line = words("Level ")
        line = line + Text("\(state.level)")
            .font(Stage.numerals(13))
            .foregroundStyle(Stage.line)
        line = line + words(". ")
        line = line + Text("\(state.scrap)")
            .font(Stage.numerals(13))
            .foregroundStyle(Stage.scrap)
        line = line + words(" scrap in hand. A part you have bought is yours for good.")
        return line
    }

    private func words(_ text: String) -> Text {
        Text(text)
            .font(Stage.body(13))
            .foregroundStyle(Stage.typeDim)
    }

    /// The five kinds as one line of words. They jump the list rather than filtering it, so every
    /// group stays in the same list and scrolling past a heading tells you where you are.
    private var categoryLine: some View {
        HStack(spacing: 16) {
            ForEach(ShopEntry.Category.allCases, id: \.self) { category in
                TextLink(heading(category), tint: Stage.typeDim) {
                    jump = category.rawValue
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - The list

    private var list: some View {
        GlassPanel(padding: 10) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(ShopEntry.Category.allCases, id: \.self) { category in
                            let rows = entries.filter { $0.category == category }
                            if !rows.isEmpty {
                                sectionHeading(heading(category))
                                    .id(category.rawValue)
                                ForEach(rows) { entry in
                                    ShopRow(
                                        entry: entry,
                                        detail: detail(entry),
                                        justBought: entry.id == justBought,
                                        shortBy: max(0, entry.price - state.scrap),
                                        onBuy: { buy(entry) }
                                    )
                                }
                            }
                        }
                        comingSoon
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: jump) { _, category in
                    guard let category else { return }
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(category, anchor: .top) }
                    jump = nil
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func sectionHeading(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(Stage.label(11))
                .kerning(Stage.Tracking.label(11))
                .foregroundStyle(Stage.typeDim)
            Rectangle()
                .fill(Stage.lineDim)
                .frame(height: 1)
        }
        .padding(.top, 8)
        .padding(.bottom, 3)
    }

    /// The parts brief v5 names that are not in the catalogue yet. They are on the ladder, so the
    /// shop says when they arrive rather than pretending the ladder stops at the last built part;
    /// each one leaves this list the moment its catalogue entry lands and becomes an ordinary row.
    @ViewBuilder
    private var comingSoon: some View {
        let known = Set(Catalogue.shared.allPartIDs)
        let ladder = ProgressionEngine.progression.levelRequired
            .filter { !known.contains($0.key) }
            .sorted { ($0.value, $0.key) < ($1.value, $1.key) }
            .map { LadderEntry(id: $0.key, level: $0.value) }
        if !ladder.isEmpty {
            sectionHeading("Still to come")
                .id("coming")
            // The reason is said ONCE, under the heading, not on every row.
            Text("These are still being built. They join the shop at these Levels.")
                .font(Stage.body(13))
                .foregroundStyle(Stage.textFaint)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            ForEach(ladder) { part in
                HStack(spacing: 10) {
                    Text(ProgressionEngine.displayName(part.id).uppercased())
                        .font(Stage.display(15))
                        .kerning(Stage.Tracking.display(15))
                        .foregroundStyle(Stage.textFaint)
                        .frame(width: 138, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Text("LEVEL \(part.level)")
                        .font(Stage.label(11))
                        .kerning(Stage.Tracking.label(11))
                        .foregroundStyle(Stage.typeDim)
                        .frame(width: 84, alignment: .trailing)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .opacity(0.62)
            }
        }
    }

    /// What the row says about the part. A weapon and a drive have the catalogue's own pips; a
    /// chassis, a utility and an armour material have none, so they get the catalogue's own
    /// sentence instead of an invented score.
    private func detail(_ entry: ShopEntry) -> ShopRow.Detail {
        switch entry.category {
        case .weapon:
            guard let weapon = Catalogue.shared.weapon(entry.id) else { return .blurb(entry.blurb) }
            return .pips([
                ShopRow.Pip(id: "Reach", filled: weapon.reachPips),
                ShopRow.Pip(id: "Hit", filled: weapon.hitPips),
                ShopRow.Pip(id: "Setup", filled: weapon.setupPips)
            ])
        case .drive:
            guard let drive = Catalogue.shared.drive(entry.id) else { return .blurb(entry.blurb) }
            return .pips([
                ShopRow.Pip(id: "Speed", filled: drive.speedPips),
                ShopRow.Pip(id: "Turn", filled: drive.turnPips),
                ShopRow.Pip(id: "Push", filled: drive.pushPips)
            ])
        case .chassis, .utility, .material:
            return .blurb(entry.blurb)
        }
    }

    /// One part on the ladder that has no catalogue entry yet.
    private struct LadderEntry: Identifiable {
        let id: String
        let level: Int
    }

    private func heading(_ category: ShopEntry.Category) -> String {
        switch category {
        case .chassis: return "Chassis"
        case .drive: return "Drive"
        case .weapon: return "Weapon"
        case .utility: return "Utility"
        case .material: return "Armour"
        }
    }

    private func buy(_ entry: ShopEntry) {
        guard CareerStore.buy(entry.id, state: state, in: context) else { return }
        justBought = entry.id
    }

    private var tickerLines: [String] {
        var lines = ["LEVEL \(state.level). \(state.scrap) SCRAP IN HAND."]
        let level = state.levelState
        if !level.isCapped {
            lines.append("\(max(1, level.pointsPerLevel - level.pointsIntoLevel)) POINTS TO LEVEL \(level.level + 1).")
        }
        lines.append("\(state.blueprints.count) OF \(Catalogue.shared.allPartIDs.count) PARTS OWNED.")
        return lines
    }
}

// MARK: - One row

/// Name, weight, what the catalogue knows, the price, and one word for what you can do. The action
/// word is in the same column on every row, so the eye scans one column to find what it can buy.
struct ShopRow: View {

    /// One of the catalogue's own 1 to 5 scores, named.
    struct Pip: Identifiable {
        let id: String
        let filled: Int
    }

    enum Detail {
        case pips([Pip])
        case blurb(String)
    }

    let entry: ShopEntry
    let detail: Detail
    var justBought = false
    var shortBy = 0
    var onBuy: () -> Void

    private var isBuyable: Bool { entry.availability == .buyable }

    var body: some View {
        Button(action: { if isBuyable { onBuy() } }) {
            HStack(spacing: 10) {
                Text(entry.name.uppercased())
                    .font(Stage.display(15))
                    .kerning(Stage.Tracking.display(15))
                    .foregroundStyle(entry.isOwned ? Stage.typeDim : Stage.type)
                    .frame(width: 138, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text(BuildRules.kilograms(entry.weight))
                    .font(Stage.numerals(13))
                    .foregroundStyle(Stage.typeDim)
                    .frame(width: 58, alignment: .trailing)

                detailView
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(entry.price)")
                    .font(Stage.numerals(13))
                    .foregroundStyle(Stage.scrap)
                    .frame(width: 46, alignment: .trailing)

                Text(action.text.uppercased())
                    .font(Stage.label(11))
                    .kerning(Stage.Tracking.label(11))
                    .foregroundStyle(action.tint)
                    .frame(width: 84, alignment: .trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                Rectangle()
                    .fill(justBought ? Stage.line.opacity(0.14) : Stage.type.opacity(0.03))
            }
            .opacity(dimmed ? 0.62 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isBuyable)
        .padding(.bottom, 4)
        .accessibilityLabel("\(entry.name), \(entry.price) scrap. \(action.spoken)")
    }

    private var dimmed: Bool {
        switch entry.availability {
        case .needsLevel, .behindWall: return true
        default: return false
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch detail {
        case .pips(let pips):
            HStack(spacing: 12) {
                ForEach(pips) { pip in
                    StatPips(label: pip.id, filled: pip.filled, width: 44)
                }
                Spacer(minLength: 0)
            }
        case .blurb(let text):
            Text(text)
                .font(Stage.body(13))
                .foregroundStyle(Stage.typeDim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// The one word at the end of the row, and what a screen reader says instead.
    private var action: (text: String, tint: Color, spoken: String) {
        if justBought { return ("Bought", Stage.win, "Bought.") }
        switch entry.availability {
        case .owned:
            return ("Owned", Stage.textFaint, "Owned already.")
        case .buyable:
            return ("Buy", Stage.line, "Buy it.")
        case .needsLevel(let level):
            return ("Level \(level)", Stage.typeDim, "Needs Level \(level).")
        case .behindWall:
            return ("Full game", Stage.typeDim, "In the full game.")
        case .tooPoor:
            return ("Costs \(entry.price)", Stage.danger, "You are \(shortBy) scrap short.")
        }
    }
}
