//
//  CareerGarageView.swift
//  The stable at the career's current capacity, the locked slots above it, and the owned parts
//  panel. Same rows and the same design system as the Stage 4 workshop; what is new is that the
//  number of slots comes from the Series and a written off machine stays on the shelf as a wreck.
//
//  Wave P (brief v5 section 9.4): parts are bought in the shop, not dripped out by a win, so the
//  Blueprints panel is now OWNED PARTS: what you hold, and for everything else the Level it needs
//  and what it costs. `CareerState.blueprints` is the owned list.
//

import SwiftUI
import SwiftData

struct CareerGarageView: View {

    @Bindable var host: ArenaHost
    let state: CareerState
    let builds: [BotBuild]
    var onBack: () -> Void

    @Environment(\.modelContext) private var context
    @State private var editing: PersistentIdentifier?
    @State private var showOwnedParts = false
    @State private var renaming = false
    @State private var draftName = ""

    private var living: [BotBuild] { builds.filter { !$0.isWrittenOff } }
    private var selected: BotBuild? { living.first { $0.isSelected } ?? living.first }
    private var lockedSlots: Int { max(0, state.garageCapacity - living.count) }

    private static let gutter: CGFloat = 26

    var body: some View {
        ZStack {
            StageBackdrop(host: host, still: .withBot, dim: 0.24)

            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 10) {
                    header
                    HStack(spacing: 0) {
                        // The machine on the shelf stands in the clear left of the picture, and
                        // that area is the turntable.
                        StageOrbitPad(host: host)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        VStack(spacing: 10) {
                            stable
                            controls
                        }
                        .frame(width: StageLayout.columnWidth(proxy.size.width - 2 * Self.gutter))
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .padding(.horizontal, Self.gutter)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            registerFocus()
            sendStage()
        }
        .onChange(of: focusKey) { _, _ in registerFocus() }
        // Picking a different machine on the shelf changes the one on the turntable.
        .onChange(of: selected?.persistentModelID) { _, _ in sendStage() }
        .fullScreenCover(item: Binding(get: { editing.map(EditingBuild.init) }, set: { editing = $0?.id })) { item in
            BuilderView(host: host, buildID: item.id)
        }
        .sheet(isPresented: $showOwnedParts) {
            OwnedPartsPanel(state: state) { showOwnedParts = false }
        }
        .alert("Rename", isPresented: $renaming) {
            TextField("Name", text: $draftName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Save") { commitRename() }
        } message: {
            Text("What is this machine called?")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            StageButton("Back", kind: .quiet, action: onBack)
                .frame(width: 96)
            Text("GARAGE")
                .font(Stage.display(24))
                .kerning(1.6)
                .foregroundStyle(Stage.text)
            Text("\(living.count) OF \(state.garageCapacity) SLOTS")
                .font(Stage.label(11))
                .foregroundStyle(Stage.textFaint)
            Spacer(minLength: 8)
            ScrapBadge(amount: state.scrap)
        }
    }

    // MARK: - The stable

    private var stable: some View {
        GlassPanel(padding: 10) {
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(builds) { build in
                        row(build)
                    }
                    ForEach(0..<lockedSlots, id: \.self) { _ in
                        emptySlot
                    }
                    if state.garageCapacity < 5 {
                        lockedSlot
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func row(_ build: BotBuild) -> some View {
        let isSelected = build.persistentModelID == selected?.persistentModelID && !build.isWrittenOff
        return Button {
            guard !build.isWrittenOff else { return }
            Garage.select(build, in: living)
            try? context.save()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                LiverySwatch(hex: build.liveryHex, size: 24, selected: isSelected)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(build.name.uppercased())
                            .font(Stage.display(17))
                            .kerning(0.8)
                            .foregroundStyle(build.isWrittenOff ? Stage.textFaint : Stage.text)
                            .strikethrough(build.isWrittenOff, color: Stage.textFaint)
                        if isSelected {
                            Text("FIGHTING")
                                .font(Stage.label(11, weight: .bold))
                                .kerning(1)
                                .foregroundStyle(Stage.ink)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Stage.line, in: CutRect(6))
                        }
                        if build.isWrittenOff {
                            Text("WRITTEN OFF")
                                .font(Stage.label(11, weight: .bold))
                                .kerning(1)
                                .foregroundStyle(Stage.danger)
                        }
                        Spacer(minLength: 4)
                        Text(BuildRules.kilograms(build.totalWeight))
                            .font(Stage.numerals(14))
                            .foregroundStyle(build.isValid ? Stage.textDim : Stage.danger)
                    }
                    Text(build.partsLine)
                        .font(Stage.label(11))
                        .foregroundStyle(Stage.textDim)
                    // Only the machine that is fighting carries its record and its damage: at
                    // 402 pt tall the list must show every slot, not one machine's life story.
                    if isSelected {
                        Text(build.recordLine)
                            .font(Stage.body(13))
                            .foregroundStyle(Stage.textFaint)
                    }
                    if !isSelected {
                        EmptyView()
                    } else if build.isWrittenOff, !build.killedBy.isEmpty {
                        Text("Killed by \(build.killedBy).")
                            .font(Stage.body(13))
                            .foregroundStyle(Stage.textFaint)
                    } else if !build.damageJSON.isEmpty {
                        Text("Carrying damage. Repair costs \(repairBill(build).total) scrap.")
                            .font(Stage.body(13))
                            .foregroundStyle(Stage.danger)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background {
                CutRect(10)
                    .fill(isSelected ? Stage.selectedFill : Stage.type.opacity(0.04))
            }
        }
        .buttonStyle(.plain)
        .opacity(build.isWrittenOff ? 0.55 : 1)
    }

    private var emptySlot: some View {
        slotRow(title: "Empty slot", detail: "Build a second machine and send whichever suits the opponent.", locked: false)
    }

    private var lockedSlot: some View {
        slotRow(
            title: "Slot locked",
            detail: "Win Series \(state.seriesIndex + 1) and the next one opens another slot.",
            locked: true
        )
    }

    private func slotRow(title: String, detail: String, locked: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: locked ? "lock.fill" : "plus.rectangle.on.rectangle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Stage.textFaint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(Stage.display(14))
                    .kerning(0.8)
                    .foregroundStyle(Stage.textFaint)
                Text(detail)
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background {
            CutRect(10)
                .fill(Stage.type.opacity(0.02))
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 8) {
            StageButton("Build", kind: .primary, enabled: selected != nil, focusID: "build") {
                editing = selected?.persistentModelID
            }
            // Two to a row: the list above gets the height (integration, 2026-09-28: at 402 pt
            // the list showed one machine and cut its second line).
            HStack(spacing: 8) {
                StageButton("New bot", enabled: living.count < state.garageCapacity, focusID: "new") {
                    addBuild()
                }
                StageButton("Owned parts", focusID: "parts") { showOwnedParts = true }
            }

            HStack(spacing: 8) {
                StageButton("Rename", kind: .quiet, enabled: selected != nil, focusID: "rename") {
                    draftName = selected?.name ?? ""
                    renaming = true
                }
                StageButton(repairTitle, kind: .quiet, enabled: canRepair, focusID: "repair") {
                    repairSelected()
                }
            }

            if living.count >= state.garageCapacity, state.garageCapacity < 5 {
                Text("Every slot is full. The next Series opens another one.")
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - The stage

    /// The chosen machine on the turntable, framed left of this screen's column.
    private func sendStage() {
        guard let selected, host.surface == .stage else { return }
        host.sendWorkshopConfig(
            selected.toBotConfig(id: CareerFightConfig.playerID, controller: "player"),
            frame: StageLayout.botFrame,
            screen: "garage"
        )
    }

    /// Changes whenever one of the controls could have changed state.
    private var focusKey: String {
        "\(living.count)-\(state.garageCapacity)-\(selected?.persistentModelID.hashValue ?? 0)-\(canRepair)"
    }

    private func registerFocus() {
        PadFocus.shared.set(
            [
                PadItem("build", enabled: selected != nil) { editing = selected?.persistentModelID },
                PadItem("new", enabled: living.count < state.garageCapacity) { addBuild() },
                PadItem("parts") { showOwnedParts = true },
                PadItem("rename", enabled: selected != nil) {
                    draftName = selected?.name ?? ""
                    renaming = true
                },
                PadItem("repair", enabled: canRepair) { repairSelected() }
            ],
            back: { onBack() }
        )
    }

    private var repairTitle: String {
        guard let selected, !selected.damageJSON.isEmpty else { return "Repair" }
        return "Repair \(repairBill(selected).total)"
    }

    private var canRepair: Bool {
        guard let selected, !selected.damageJSON.isEmpty, !selected.isWrittenOff else { return false }
        return state.scrap >= repairBill(selected).total
    }

    private func repairBill(_ build: BotBuild) -> RepairBill {
        CareerEngine.repairBill(for: build.spec, damage: build.currentDamage)
    }

    private func repairSelected() {
        guard let selected else { return }
        CareerStore.repair(selected, bill: repairBill(selected), state: state, in: context)
    }

    private func addBuild() {
        guard living.count < state.garageCapacity else { return }
        let build = BotBuild(spec: .defaultWedge)
        build.name = "Machine \(living.count + 1)"
        context.insert(build)
        Garage.select(build, in: living + [build])
        try? context.save()
        editing = build.persistentModelID
    }

    private func commitRename() {
        guard let selected else { return }
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selected.name = String(trimmed.prefix(18))
        try? context.save()
    }
}

/// `fullScreenCover(item:)` needs an Identifiable, and `PersistentIdentifier` is not one.
private struct EditingBuild: Identifiable {
    let id: PersistentIdentifier
}

// MARK: - Blueprints

/// Everything the player owns, and everything they do not, with the Level it needs and what it
/// costs in the shop (brief v5 section 7).
struct OwnedPartsPanel: View {

    let state: CareerState
    var onClose: () -> Void

    private var catalogue: Catalogue { Catalogue.shared }

    var body: some View {
        ZStack {
            Stage.ground.ignoresSafeArea()
            StageStill(kind: .empty).opacity(0.3).ignoresSafeArea()
            Stage.ink.opacity(0.70).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    StageButton("Close", kind: .quiet, action: onClose)
                        .frame(width: 100)
                    Text("OWNED PARTS")
                        .font(Stage.display(22))
                        .kerning(1.6)
                        .foregroundStyle(Stage.text)
                    Spacer(minLength: 8)
                    Text("\(state.blueprints.count) OF \(everyPartCount) PARTS OWNED")
                        .font(Stage.label(11))
                        .foregroundStyle(Stage.textFaint)
                }

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        group("Chassis", catalogue.chassis.map { ($0.id, $0.name) })
                        group("Drive", catalogue.drives.map { ($0.id, $0.name) })
                        group("Weapon", catalogue.weapons.map { ($0.id, $0.name) })
                        group("Utility", catalogue.utilities.map { ($0.id, $0.name) })
                        group("Armour", catalogue.materials.map { ($0.id, $0.name) })
                    }
                    .padding(.bottom, 4)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .preferredColorScheme(.dark)
    }

    private var everyPartCount: Int {
        catalogue.chassis.count + catalogue.drives.count + catalogue.weapons.count
            + catalogue.utilities.count + catalogue.materials.count
    }

    private func group(_ title: String, _ parts: [(String, String)]) -> some View {
        GlassPanel(padding: 10) {
            VStack(alignment: .leading, spacing: 5) {
                StageHeading(title)
                ForEach(parts, id: \.0) { part in
                    row(id: part.0, name: part.1)
                }
            }
            .frame(width: 164, alignment: .leading)
        }
    }

    private func row(id: String, name: String) -> some View {
        let held = state.unlocks(id)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: held ? "checkmark" : "lock.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(held ? Stage.text : Stage.textFaint)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(name.uppercased())
                    .font(Stage.display(13))
                    .kerning(0.5)
                    .foregroundStyle(held ? Stage.text : Stage.textFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(BroadcastType.floorScale(.display, size: 13, wanted: 0.7))
                if !held {
                    Text(CareerUnlocks.lockNote(for: id))
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.textFaint)
                        .lineLimit(1)
                        .minimumScaleFactor(BroadcastType.floorScale(.body, size: 13, wanted: 0.7))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Locks in the builder

/// What the player may fit, and the sentence that says when the rest arrives.
enum CareerUnlocks {

    /// Everything the player holds. With no career yet that is the starting unlocks, because
    /// nothing has been earned.
    static func held(_ state: CareerState?) -> Set<String> {
        guard let state else { return Set(CareerCatalogue.shared.startingUnlocks) }
        return state.unlocked
    }

    /// "Level 25 in the shop", for a picker row of a part the player does not own yet. Wave P
    /// (brief v5 section 7): a part is not earned by a win any more, it is bought in the shop once
    /// the Level allows it, so the note says the Level and the price rather than a Series.
    static func lockNote(for partID: String) -> String {
        // P6 (stage 6, the wall): while the game is locked, a part outside the free library is not
        // waiting on a Level the player can reach, it is behind the purchase, and the row has to
        // say so (brief section 14). One line, and it does nothing once the game is unlocked.
        if let wall = Gates.snapshot.lockedReasonIfLocked(.part(partID)) { return wall }
        let level = ProgressionEngine.levelRequired(partID)
        let price = ProgressionEngine.price(partID)
        if level > 1 { return "Level \(level) in the shop" }
        return price > 0 ? "In the shop for \(price)" : "In the shop"
    }
}

/// Greys a picker row out and stops it being chosen, with the tier that earns it on the row.
struct LockGate<Content: View>: View {
    let locked: Bool
    let partID: String
    @ViewBuilder var content: Content

    var body: some View {
        content
            .opacity(locked ? 0.34 : 1)
            .allowsHitTesting(!locked)
            .overlay(alignment: .topTrailing) {
                if locked {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(CareerUnlocks.lockNote(for: partID).uppercased())
                            .font(Stage.label(11, weight: .bold))
                            .kerning(0.6)
                    }
                    .foregroundStyle(Stage.text)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Stage.glassDeep, in: CutRect(6))
                    .padding(6)
                }
            }
            .accessibilityHint(locked ? CareerUnlocks.lockNote(for: partID) : "")
    }
}
