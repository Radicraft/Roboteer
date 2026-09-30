//
//  ShopView.swift
//  The shop (brief v5 sections 3, 7 and 9.4), drawn as direction A, "Blueprint overlay"
//  (docs/look/menus-blueprint.html, wave C): the stage pulls the category's part out of the
//  machine in the middle of the screen, a detail plate on the left says what the part being looked
//  at is, and one plate on the right lists the category with the tabs over it and BUY FOR under it.
//
//  A row is the part's glyph, its name and one figure: the price, OWNED, or the Level it needs with
//  the price dimmed. A part that cannot be afforded yet shows its price in danger and how much more
//  is needed. Tapping a row looks at it; the primary buys it.
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
    @Query(sort: \BotBuild.createdAt, order: .forward) private var builds: [BotBuild]

    /// The part the player just bought, so the row can say so for a moment.
    @State private var justBought: String = ""
    /// The tab: a category's raw value, or "coming" for the parts still being built.
    @State private var tab: String = ShopView.initialTab
    /// The part being looked at in the tab, or nil for the tab's first.
    @State private var looking: String?
    @State private var keepOut = LeaderKeepOut()

    private var gates: Gates { Gates.snapshot }
    private var entries: [ShopEntry] { ProgressionEngine.shopEntries(state: state, gates: gates) }
    private var machine: BotBuild? { Garage.selected(from: builds.filter { !$0.isWrittenOff }) }

    /// QA (docs/qa-launch-flags.md): `-shopAt weapon` opens the shop on that tab.
    private static var initialTab: String {
        let asked = ArenaHost.launchArgument("-shopAt") ?? ""
        if asked == "coming" || ShopEntry.Category(rawValue: asked) != nil { return asked }
        return ShopEntry.Category.weapon.rawValue
    }

    /// The `focus` the stage is told when the shop opens on its first tab.
    static var stageFocus: String? {
        switch initialTab {
        case "material": return "armour"
        case "coming": return nil
        default: return initialTab
        }
    }

    private static let tabs: [String] = ShopEntry.Category.allCases.map(\.rawValue) + ["coming"]

    var body: some View {
        ZStack {
            StageBackdrop(host: host, still: .empty, dim: 0, shade: .right)

            GeometryReader { proxy in
                let compact = proxy.size.height < 400
                ZStack(alignment: .topLeading) {
                    StageLeaderLayer(anchors: host.stageAnchors, screen: "shop",
                                     leaders: shopLeaders, keepOut: keepOut)
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                            header
                            detailPlate(compact: compact)
                                .frame(width: min(250, proxy.size.width * 0.3))
                                .leaderKeepOut(keepOut, "detail")
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        VStack(alignment: .trailing, spacing: 8) {
                            BlueprintScrapBlock(amount: state.scrap)
                                .leaderKeepOut(keepOut, "scrap")
                            listPlate
                                .leaderKeepOut(keepOut, "list")
                            primary
                                .leaderKeepOut(keepOut, "primary")
                        }
                        .frame(width: min(314, (proxy.size.width * 0.4).rounded()))
                    }
                    .padding(.top, compact ? 12 : 16)
                    .padding(.bottom, compact ? 4 : 10)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            registerFocus()
            announce()
        }
        .onChange(of: tab) { _, _ in
            looking = nil
            announce()
        }
    }

    /// The stage pulls the tab's category out of the machine (docs/wave-c-menus-notes.md).
    private func announce() {
        let focus: String?
        switch tab {
        case "material": focus = "armour"
        case "coming": focus = nil
        default: focus = tab
        }
        host.enterStageScreen("shop", focus: focus)
    }

    private func registerFocus() {
        PadFocus.shared.set(
            [PadItem("shop.buy") { buyLooked() }],
            back: { onClose() },
            sideways: { event in
                guard let index = Self.tabs.firstIndex(of: tab) else { return false }
                let next = (index + (event == .left ? -1 : 1) + Self.tabs.count) % Self.tabs.count
                tab = Self.tabs[next]
                return true
            }
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            BackChevron(action: onClose)
            VStack(alignment: .leading, spacing: 4) {
                Text("Shop")
                    .font(Blueprint.display(28))
                    .foregroundStyle(Color.white)
                (Text("Level ") + Text("\(state.level)").font(Blueprint.mono(13.5)).foregroundStyle(Color.white)
                 + Text(". A part you buy is yours for good."))
                    .font(Blueprint.body(13.5))
                    .foregroundStyle(Blueprint.dim)
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.top, -2)
        }
        .leaderKeepOut(keepOut, "header")
    }

    // MARK: - The list

    private var tabEntries: [ShopEntry] {
        guard let category = ShopEntry.Category(rawValue: tab) else { return [] }
        return entries.filter { $0.category == category }
    }

    private var lookedAt: ShopEntry? {
        let rows = tabEntries
        if let looking, let hit = rows.first(where: { $0.id == looking }) { return hit }
        return rows.first(where: { $0.availability == .buyable })
            ?? rows.first(where: { $0.availability == .tooPoor })
            ?? rows.first
    }

    private var listPlate: some View {
        VStack(alignment: .leading, spacing: 0) {
            StageSegments(values: Self.tabs, title: { tabTitle($0) }, selection: $tab, size: 11)
                .padding(.bottom, 8)
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 0) {
                        if tab == "coming" {
                            comingSoon
                        } else {
                            ForEach(Array(tabEntries.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { BlueprintRule() }
                                row(entry).id(entry.id)
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .onAppear { if let id = lookedAt?.id { reader.scrollTo(id, anchor: .center) } }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .blueprintPlate()
    }

    private func tabTitle(_ id: String) -> String {
        switch id {
        case "chassis": return "Chassis"
        case "drive": return "Drive"
        case "weapon": return "Weapon"
        case "utility": return "Utility"
        case "material": return "Armour"
        default: return "Later"
        }
    }

    private func row(_ entry: ShopEntry) -> some View {
        let isLooked = entry.id == lookedAt?.id
        let rowState: BlueprintPartRow<AnyView>.State
        var note = ""
        var noteTint: Color? = nil
        switch entry.availability {
        case .owned: rowState = isLooked ? .selected : .owned
        case .buyable: rowState = isLooked ? .selected : .normal
        case .needsLevel, .behindWall: rowState = .locked
        case .tooPoor:
            rowState = isLooked ? .selected : .poor
            note = "Need \(max(0, entry.price - state.scrap)) more"
            noteTint = Blueprint.dim
        }
        if entry.id == justBought {
            note = "Bought"
            noteTint = Color.white
        }
        return BlueprintPartRow(glyph: glyph(entry), name: entry.name, note: note, noteTint: noteTint,
                                state: rowState) {
            AnyView(trailing(entry))
        } action: {
            looking = entry.id
        }
        .accessibilityLabel("\(entry.name), \(entry.price) scrap. \(spoken(entry))")
    }

    @ViewBuilder
    private func trailing(_ entry: ShopEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch entry.availability {
            case .owned:
                Text("Owned").font(Blueprint.ui(12.5)).foregroundStyle(Blueprint.dim)
            case .buyable:
                Text("\(entry.price)").font(Blueprint.mono(14)).foregroundStyle(Color.white)
            case .tooPoor:
                Text("\(entry.price)").font(Blueprint.mono(14)).foregroundStyle(Blueprint.danger)
            case .needsLevel(let level):
                Text("Level \(level)").font(Blueprint.ui(12.5)).foregroundStyle(Blueprint.dim)
                Text("\(entry.price)").font(Blueprint.mono(12)).foregroundStyle(Color.white).opacity(0.4)
            case .behindWall:
                Text("Full game").font(Blueprint.ui(12.5)).foregroundStyle(Blueprint.dim)
                Text("\(entry.price)").font(Blueprint.mono(12)).foregroundStyle(Color.white).opacity(0.4)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func spoken(_ entry: ShopEntry) -> String {
        if entry.id == justBought { return "Bought." }
        switch entry.availability {
        case .owned: return "Owned already."
        case .buyable: return "Buy it."
        case .needsLevel(let level): return "Needs Level \(level)."
        case .behindWall: return "In the full game."
        case .tooPoor: return "You are \(max(0, entry.price - state.scrap)) scrap short."
        }
    }

    /// The manifest's glyph for a weapon or a utility row (design system section 6). A chassis,
    /// a drive and an armour plate have none drawn, and a row with no glyph keeps the column empty.
    private func glyph(_ entry: ShopEntry) -> GlyphArt? {
        switch entry.category {
        case .weapon: return BroadcastGlyph.weapon(entry.id)
        case .utility: return BroadcastGlyph.utility(entry.id)
        default: return nil
        }
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
        Text(ladder.isEmpty ? "Every part on the ladder is in the shop."
                            : "These are still being built. They join the shop at these Levels.")
            .font(Blueprint.body(13))
            .foregroundStyle(Blueprint.dim)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        ForEach(Array(ladder.enumerated()), id: \.element.id) { index, part in
            if index > 0 { BlueprintRule() }
            BlueprintPartRow(glyph: nil, name: ProgressionEngine.displayName(part.id), state: .locked) {
                Text("Level \(part.level)").font(Blueprint.ui(12.5)).foregroundStyle(Blueprint.dim)
            } action: {}
            .allowsHitTesting(false)
        }
    }

    /// One part on the ladder that has no catalogue entry yet.
    private struct LadderEntry: Identifiable {
        let id: String
        let level: Int
    }

    // MARK: - The detail plate

    /// "Detail. Weapon, Saw, 12 kg", the glyph large, the part's own numbers and its sentence.
    @ViewBuilder
    private func detailPlate(compact: Bool) -> some View {
        if let entry = lookedAt, tab != "coming" {
            VStack(alignment: .leading, spacing: 6) {
                (Text("Detail. \(tabTitle(tab)), \(entry.name), ")
                 + Text(BuildRules.kilograms(entry.weight)).font(Blueprint.mono(12)))
                    .font(Blueprint.ui(12))
                    .foregroundStyle(Blueprint.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let art = glyph(entry), !compact {
                    GlyphMark(art: art, size: 64, tint: Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                let stats = detailStats(entry)
                if !stats.isEmpty {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(stats, id: \.0) { stat in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stat.0).font(Blueprint.ui(11.5)).foregroundStyle(Blueprint.dim)
                                Text(stat.1)
                                    .font(Stage.figure(stat.1, size: 17.5))
                                    .foregroundStyle(Color.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    }
                }
                Text(entry.blurb)
                    .font(Blueprint.body(13))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .blueprintPlate()
        }
    }

    private func detailStats(_ entry: ShopEntry) -> [(String, String)] {
        let catalogue = Catalogue.shared
        switch entry.category {
        case .weapon:
            guard let weapon = catalogue.weapon(entry.id) else { return [] }
            var out = [("Reach", "\(Int((weapon.reach * 1000).rounded())) mm"), ("Hit", "\(weapon.hitPips) of 5")]
            if weapon.setupSeconds > 0 { out.append(("Reset", String(format: "%.1f s", weapon.setupSeconds))) }
            return out
        case .drive:
            guard let drive = catalogue.drive(entry.id) else { return [] }
            return [("Speed", "\(drive.speedPips) of 5"), ("Turn", "\(drive.turnPips) of 5"), ("Push", "\(drive.pushPips) of 5")]
        case .chassis:
            guard let chassis = catalogue.chassis(entry.id) else { return [] }
            return [("Clearance", "\(Int((chassis.clearanceFront * 1000).rounded())) mm")]
        case .utility, .material:
            return []
        }
    }

    // MARK: - The primary

    @ViewBuilder
    private var primary: some View {
        if let entry = lookedAt, tab != "coming" {
            switch entry.availability {
            case .buyable:
                primaryPlate("Buy for", "\(entry.price)", enabled: true) { buy(entry) }
            case .owned:
                primaryPlate(entry.id == justBought ? "Bought" : "Owned", "", enabled: false) {}
            case .tooPoor:
                primaryPlate("Need", "\(max(0, entry.price - state.scrap)) more", enabled: false) {}
            case .needsLevel(let level):
                primaryPlate("Opens at Level", "\(level)", enabled: false) {}
            case .behindWall:
                primaryPlate("In the full game", "", enabled: false) {}
            }
        } else {
            primaryPlate("Back", "", enabled: true) { onClose() }
        }
    }

    private func primaryPlate(_ title: String, _ figure: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { if enabled { action() } }) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).lineLimit(1).minimumScaleFactor(0.6)
                if !figure.isEmpty {
                    Text(figure).font(Blueprint.mono(18))
                }
            }
        }
        .buttonStyle(BroadcastButtonStyle(kind: .primary, enabled: enabled,
                                          focused: PadFocus.shared.isFocused("shop.buy")))
        .disabled(!enabled)
        .accessibilityLabel("\(title) \(figure)")
    }

    private func buyLooked() {
        guard let entry = lookedAt, entry.availability == .buyable else { return }
        buy(entry)
    }

    private func buy(_ entry: ShopEntry) {
        guard CareerStore.buy(entry.id, state: state, in: context) else { return }
        justBought = entry.id
        looking = entry.id
    }

    // MARK: - The leader

    /// The category's part on the machine, and what is fitted there now.
    private var shopLeaders: [Leader] {
        guard let machine else { return [] }
        let catalogue = Catalogue.shared
        switch tab {
        case "weapon":
            let mount = catalogue.chassis(machine.chassisID)?.mountWeapon ?? "front"
            let word = mount == "top" ? "Top" : (mount == "shell" ? "Shell" : "Front")
            return [Leader(id: "focus", target: .partOrPoint("weapon", "weapon"), title: "\(word) mount",
                           value: "\(catalogue.weapon(machine.weaponID)?.name ?? "Weapon") fitted", dx: 68, dy: 56)]
        case "drive":
            return [Leader(id: "focus", target: .kind("wheel", prefer: ["wheel_fl", "wheel_rl", "track_l"]), title: "Drive",
                           value: "\(catalogue.drive(machine.driveID)?.name ?? "Drive") fitted", dx: 68, dy: 56)]
        case "chassis":
            return [Leader(id: "focus", target: .partOrPoint("chassis", "centre"), title: "Hull",
                           value: "\(catalogue.chassis(machine.chassisID)?.name ?? "Hull") fitted", dx: 68, dy: 56)]
        case "utility":
            let fitted = machine.utilities.compactMap { catalogue.utility($0)?.name }
            return [Leader(id: "focus", target: .partOrPoint("utility", "centre"), title: "Utility",
                           value: fitted.isEmpty ? "Both slots free" : fitted.joined(separator: ", "), dx: 68, dy: 56)]
        case "material":
            let material = catalogue.material(machine.topMaterial)?.name ?? machine.topMaterial.capitalized
            return [Leader(id: "focus", target: .partOrPoint("armour_top", "top"), title: "Top armour",
                           value: "\(material), \(machine.topThickness == 1 ? "1 unit" : "\(machine.topThickness) units")",
                           dx: 68, dy: -56)]
        default:
            return []
        }
    }
}
