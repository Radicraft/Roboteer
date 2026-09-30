//
//  WorkshopView.swift
//  The stable. Which machine you fight with, and the way into the builder, the test arena and a
//  fight. Capacity is one bot in Stage 4, so the second row is the locked garage slot and the
//  layout is already the Stage 5 layout.
//

import SwiftUI
import SwiftData

struct WorkshopView: View {

    @Bindable var host: ArenaHost
    var onBuild: (BotBuild) -> Void
    var onTest: () -> Void
    var onFight: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \BotBuild.createdAt, order: .forward) private var builds: [BotBuild]
    /// The career, whose scrap pays for a repair here exactly as it does in the career (owner
    /// decision 2, bug 2 of docs/aaa/frontend-meta.md: this button used to repair for free).
    @Query private var careers: [CareerState]

    @State private var renaming = false
    @State private var draftName = ""
    @State private var confirmingDelete = false

    /// Owner decision 12: one garage, so the Workshop has the career's slots (bug 11 of
    /// docs/aaa/frontend-meta.md: this was a fixed 1).
    private var capacity: Int { Garage.capacity(career: careers.first, gates: Gates.snapshot) }
    /// Scrapping the last machine would leave nothing to fight with.
    private var canDelete: Bool { selected != nil && Garage.canDelete(builds) }

    private var selected: BotBuild? { Garage.selected(from: builds) }
    private var living: [BotBuild] { builds.filter { !$0.isWrittenOff } }

    /// What opens the next slot: the full game, or the next Series.
    private var nextSlotLine: String {
        let gates = Gates.snapshot
        if !gates.isUnlocked, capacity >= Gates.freeGarageCapacity {
            return gates.lockedReason(.garageSlot(capacity + 1))
        }
        return "Slot \(capacity + 1) opens with the next Series."
    }

    /// The selected machine first, then the rest in the order they were built.
    private var ordered: [BotBuild] {
        guard let selected else { return builds }
        return [selected] + builds.filter { $0.persistentModelID != selected.persistentModelID }
    }

    var body: some View {
        ZStack {
            StageBackdrop(host: host, still: .withBot, dim: 0.22)

            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 12) {
                    header
                    HStack(spacing: 0) {
                        // The left of the screen is the machine. Nothing is drawn over it: this is
                        // the whole point of the workshop, and the first build hid it behind the
                        // list (owner, 2026-09-14). The clear area is the turntable's, so a drag
                        // here turns the machine rather than doing nothing.
                        StageOrbitPad(host: host)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        column(height: proxy.size.height)
                            .frame(width: StageLayout.columnWidth(proxy.size.width - 2 * Self.gutter))
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .padding(.horizontal, Self.gutter)
                .padding(.vertical, 16)
                // Top aligned inside the whole screen. Without this the stack is centred in the
                // ZStack, so anything taller than the screen loses its title off the top rather
                // than its last control off the bottom.
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
        // The workshop owns what stands on the stage while it is up: its own machine, framed left
        // of the panels. Without this send it inherits the menu's framing and a bot picked here
        // would never reach the turntable.
        .onChange(of: stageKey) { _, _ in sendStage() }
        .alert("Rename", isPresented: $renaming) {
            TextField("Name", text: $draftName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Save") { commitRename() }
        } message: {
            Text("What is this machine called?")
        }
        .confirmationDialog(
            "Scrap \(selected?.name ?? "this bot")?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Scrap it", role: .destructive) { deleteSelected() }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The build and its record are gone for good.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            StageButton("Back", kind: .quiet) { dismiss() }
                .frame(width: 104)

            Text("WORKSHOP")
                .font(Stage.display(28))
                .kerning(1.8)
                .foregroundStyle(Stage.text)

            Spacer(minLength: 8)

            PadHintBar()

            if let selected {
                WeightBar(used: selected.totalWeight, compact: true)
                    .frame(width: 240)
            }
        }
    }

    // MARK: - The right hand column

    private static let gutter: CGFloat = 26

    /// One column: the stable on top, the controls under it. Both are the width of the column, so
    /// the left of the screen stays clear from the header row down.
    ///
    /// The arithmetic, because the first build gave the list 28 pt and showed no rows at all.
    /// 402 pt tall (iPhone 17): 402 - 32 (the screen's own vertical padding) - 34 (header)
    /// - 12 (stack spacing) - 10 (column spacing) = 314 pt for the list and the buttons together.
    /// The buttons are 48 + 44 + 44 + 38 with three 7 pt gaps = 195 pt, which leaves the list
    /// 119 pt: one compact row (60 pt) and the locked slot under it. With the damage caption
    /// (20 pt) that is 99 pt, still two rows' worth.
    /// 375 pt tall (iPhone SE, the shortest iOS 18 landscape): 287 - 195 = 92 pt, one full row and
    /// the top of the next, and the caption and the record lines are dropped at that height.
    /// So the list's floor is 92 pt and it holds a higher layout priority than the buttons: if
    /// anything has to give it is the list's scroll, never the rows disappearing altogether.
    private func column(height: CGFloat) -> some View {
        let compact = height < 390
        return VStack(spacing: 10) {
            list(showsRecord: !compact)
                .frame(minHeight: 92)
                .layoutPriority(1)
            controls(compact: compact)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - The stable

    private func list(showsRecord: Bool) -> some View {
        GlassPanel(padding: 9) {
            ScrollView {
                VStack(spacing: 6) {
                    // The machine you fight with is the one you came to look at, so it is the row
                    // at the top whatever order the garage was built in.
                    ForEach(ordered) { build in
                        row(build, showsRecord: showsRecord)
                    }
                    // One row for the next slot the garage does not have yet, when there is one.
                    if living.count >= capacity, capacity < 5 {
                        lockedRow
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        // The list takes what is left after the buttons, rather than the buttons taking what is
        // left after the list: the buttons are the reason the screen exists.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Two lines: what it is called and what it weighs, then what it is made of. The record line
    /// is the first thing to go when the column is short, because it is history rather than a
    /// choice.
    private func row(_ build: BotBuild, showsRecord: Bool) -> some View {
        let isSelected = build.persistentModelID == selected?.persistentModelID
        return Button {
            Garage.select(build, in: builds)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                LiverySwatch(hex: build.liveryHex, size: 22, selected: isSelected)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(build.name.uppercased())
                            .font(Stage.display(17))
                            .kerning(1)
                            .foregroundStyle(Stage.text)
                            .lineLimit(1)
                            .minimumScaleFactor(BroadcastType.floorScale(.display, size: 17, wanted: 0.7))
                        if isSelected {
                            Text("FIGHTING")
                                .font(Stage.label(11, weight: .bold))
                                .kerning(1)
                                .foregroundStyle(Stage.ink)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Stage.line, in: CutRect(6))
                        }
                        Spacer(minLength: 4)
                        Text(BuildRules.kilograms(build.totalWeight))
                            .font(Stage.numerals(14))
                            .foregroundStyle(build.isValid ? Stage.text : Stage.danger)
                    }
                    Text(build.partsLine)
                        .font(Stage.label(11))
                        .foregroundStyle(Stage.textDim)
                        .lineLimit(1)
                        .minimumScaleFactor(BroadcastType.floorScale(.label, size: 11, wanted: 0.75))
                    if showsRecord {
                        Text(build.recordLine)
                            .font(Stage.body(13))
                            .foregroundStyle(Stage.textFaint)
                            .lineLimit(1)
                    }
                    if !build.isValid, let first = BuildRules.errors(build.spec).first {
                        Text(first)
                            .font(Stage.body(13))
                            .foregroundStyle(Stage.danger)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background {
                CutRect(10)
                    .fill(isSelected ? Stage.selectedFill : Stage.type.opacity(0.04))
            }
        }
        .buttonStyle(.plain)
    }

    private var lockedRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Stage.textFaint)
            VStack(alignment: .leading, spacing: 1) {
                Text("GARAGE SLOT LOCKED")
                    .font(Stage.display(14))
                    .kerning(1)
                    .foregroundStyle(Stage.textFaint)
                Text(nextSlotLine)
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.textFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(BroadcastType.floorScale(.body, size: 13, wanted: 0.8))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background {
            CutRect(10)
                .fill(Stage.type.opacity(0.02))
        }
        .accessibilityLabel("Garage slot locked")
    }

    // MARK: - Controls

    /// Under the list, the full width of the column, at the heights the arithmetic in `column`
    /// depends on: 48 for the one call to action, 44 for the other two, one 38 pt row of four quiet
    /// actions. The four used to be two rows of two, which cost another 45 pt and left the list
    /// with nothing to show.
    private func controls(compact: Bool) -> some View {
        VStack(spacing: 7) {
            StageButton("Build", kind: .primary, enabled: selected != nil, focusID: "build") {
                if let selected { onBuild(selected) }
            }
            .frame(height: 48)

            // Side by side, so the list above has room for two whole machine rows on a 402 pt
            // phone rather than one and half of the next (QA 2026-09-25).
            HStack(spacing: 6) {
                StageButton("Test in the arena", enabled: selected?.isValid ?? false, focusID: "test") { onTest() }
                StageButton("Fight", enabled: selected?.isValid ?? false, focusID: "fight") { onFight() }
                    .frame(maxWidth: 150)
            }
            .frame(height: 44)

            HStack(spacing: 6) {
                StageButton("Rename", kind: .quiet, enabled: selected != nil, focusID: "rename") {
                    draftName = selected?.name ?? ""
                    renaming = true
                }
                StageButton("New bot", kind: .quiet, enabled: living.count < capacity, focusID: "new") {
                    addBuild()
                }
                StageButton("Delete", kind: .quiet, enabled: canDelete, focusID: "delete") {
                    confirmingDelete = true
                }
                StageButton(repairTitle, kind: .quiet, enabled: canRepair, focusID: "repair") {
                    repairSelected()
                }
            }
            .frame(height: 38)

            // The damage note is a caption under the row that acts on it, and only when the column
            // is tall enough to spare the 20 pt.
            if !compact, let selected, !selected.damageJSON.isEmpty {
                Text(damageNote(selected))
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.textDim)
                    .lineLimit(1)
                    .minimumScaleFactor(BroadcastType.floorScale(.body, size: 13, wanted: 0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - The stage

    /// A cheap value that changes when the machine on the stage should change.
    private var stageKey: String {
        guard let selected else { return "" }
        return "\(selected.persistentModelID.hashValue)-\(selected.liveryHex)-\(selected.partsLine)"
    }

    /// Put the selected machine on the turntable, framed at 28 % across so it stands clear of this
    /// screen's column rather than behind it.
    private func sendStage() {
        guard let selected, host.surface == .stage else { return }
        host.sendWorkshopConfig(
            selected.toBotConfig(id: FightConfigFixture.playerID, controller: "player"),
            frame: StageLayout.botFrame,
            screen: "workshop"
        )
    }

    // MARK: - Pad

    /// Changes whenever a control's enabled state could have changed.
    private var focusKey: String {
        let selected = self.selected
        return "\(selected?.persistentModelID.hashValue ?? 0)-\(selected?.isValid ?? false)-\(builds.count)-\(selected?.damageJSON.isEmpty ?? true)-\(canRepair)"
    }

    private func registerFocus() {
        PadFocus.shared.set(
            [
                PadItem("build", enabled: selected != nil) { if let selected { onBuild(selected) } },
                PadItem("test", enabled: selected?.isValid ?? false) { onTest() },
                PadItem("fight", enabled: selected?.isValid ?? false) { onFight() },
                PadItem("rename", enabled: selected != nil) {
                    draftName = selected?.name ?? ""
                    renaming = true
                },
                PadItem("new", enabled: living.count < capacity) { addBuild() },
                PadItem("delete", enabled: canDelete) { confirmingDelete = true },
                PadItem("repair", enabled: canRepair) { repairSelected() }
            ],
            back: { dismiss() }
        )
    }

    // MARK: - Repair (owner decision 2: the Workshop charges the career bill)

    private var selectedBill: RepairBill {
        guard let selected else { return RepairBill() }
        return CareerEngine.repairBill(for: selected.spec, damage: selected.currentDamage)
    }

    private var bank: Int { careers.first?.scrap ?? CareerStore.openingScrap }

    private var canRepair: Bool {
        guard let selected, !selected.damageJSON.isEmpty else { return false }
        return bank >= selectedBill.total
    }

    private var repairTitle: String {
        guard let selected, !selected.damageJSON.isEmpty, selectedBill.total > 0 else { return "Repair" }
        return "Repair \(selectedBill.total)"
    }

    private func damageNote(_ build: BotBuild) -> String {
        let bill = selectedBill.total
        if bank < bill { return "Repairs cost \(bill) scrap and there is \(bank) in the bank." }
        return "\(build.name) is carrying damage. Repairs cost \(bill) scrap."
    }

    /// The same call the career makes, so there is one place a bill is paid.
    private func repairSelected() {
        guard let selected, canRepair else { return }
        let state = CareerStore.state(in: context)
        CareerStore.repair(selected, bill: selectedBill, state: state, in: context)
    }

    // MARK: - Actions

    private func addBuild() {
        guard living.count < capacity else { return }
        let build = BotBuild(spec: .defaultWedge)
        context.insert(build)
        Garage.select(build, in: builds + [build])
        try? context.save()
    }

    private func commitRename() {
        guard let selected else { return }
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selected.name = String(trimmed.prefix(18))
        try? context.save()
    }

    private func deleteSelected() {
        guard let selected, canDelete else { return }
        let remaining = builds.filter { $0.persistentModelID != selected.persistentModelID }
        context.delete(selected)
        if let next = remaining.first {
            Garage.select(next, in: remaining)
        }
        try? context.save()
    }
}
