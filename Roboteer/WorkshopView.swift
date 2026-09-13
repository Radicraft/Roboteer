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

    @State private var renaming = false
    @State private var draftName = ""
    @State private var confirmingDelete = false

    /// One machine at a time in Stage 4. Stage 5 raises this.
    private let capacity = 1

    private var selected: BotBuild? { Garage.selected(from: builds) }

    var body: some View {
        ZStack {
            StageBackdrop(host: host, still: .withBot, dim: 0.34)

            VStack(alignment: .leading, spacing: 14) {
                header
                HStack(alignment: .top, spacing: 22) {
                    list
                    controls
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 20)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
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

            if let selected {
                WeightBar(used: selected.totalWeight, compact: true)
                    .frame(width: 260)
            }
        }
    }

    // MARK: - The stable

    private var list: some View {
        GlassPanel(padding: 12) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(builds) { build in
                        row(build)
                    }
                    ForEach(0..<max(0, capacity + 1 - builds.count), id: \.self) { _ in
                        lockedRow
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func row(_ build: BotBuild) -> some View {
        let isSelected = build.persistentModelID == selected?.persistentModelID
        return Button {
            Garage.select(build, in: builds)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                LiverySwatch(hex: build.liveryHex, size: 26, selected: isSelected)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(build.name.uppercased())
                            .font(Stage.display(18))
                            .kerning(1)
                            .foregroundStyle(Stage.text)
                        if isSelected {
                            Text("FIGHTING")
                                .font(Stage.label(9, weight: .bold))
                                .kerning(1)
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Stage.text, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                        Spacer(minLength: 4)
                        Text(BuildRules.kilograms(build.totalWeight))
                            .font(Stage.numerals(15))
                            .foregroundStyle(build.isValid ? Stage.text : Stage.danger)
                    }
                    Text(build.partsLine)
                        .font(Stage.label(12))
                        .foregroundStyle(Stage.textDim)
                    Text(build.recordLine)
                        .font(Stage.body(11))
                        .foregroundStyle(Stage.textFaint)
                    if !build.isValid, let first = BuildRules.errors(build.spec).first {
                        Text(first)
                            .font(Stage.body(11))
                            .foregroundStyle(Stage.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.12 : 0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Stage.edgeBright : Stage.edge, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var lockedRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Stage.textFaint)
            VStack(alignment: .leading, spacing: 3) {
                Text("GARAGE SLOT LOCKED")
                    .font(Stage.display(15))
                    .kerning(1)
                    .foregroundStyle(Stage.textFaint)
                Text("One machine at a time for now. More slots open later.")
                    .font(Stage.body(11))
                    .foregroundStyle(Stage.textFaint)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.02))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Stage.edge, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .accessibilityLabel("Garage slot locked")
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 9) {
            StageButton("Build", kind: .primary, enabled: selected != nil) {
                if let selected { onBuild(selected) }
            }
            StageButton("Test in the arena", enabled: selected?.isValid ?? false) { onTest() }
            StageButton("Fight", enabled: selected?.isValid ?? false) { onFight() }

            HStack(spacing: 8) {
                StageButton("Rename", kind: .quiet, enabled: selected != nil) {
                    draftName = selected?.name ?? ""
                    renaming = true
                }
                StageButton("New bot", kind: .quiet, enabled: builds.count < capacity) {
                    addBuild()
                }
            }

            StageButton("Delete", kind: .danger, enabled: selected != nil) {
                confirmingDelete = true
            }

            Spacer(minLength: 0)

            if let selected, !selected.damageJSON.isEmpty {
                GlassPanel(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        StageHeading("Between fights")
                        Text("\(selected.name) is carrying damage from the last fight.")
                            .font(Stage.body(11))
                            .foregroundStyle(Stage.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                        StageButton("Repair", kind: .quiet) { selected.repair() }
                    }
                }
            }
        }
        .frame(width: 236)
    }

    // MARK: - Actions

    private func addBuild() {
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
        guard let selected else { return }
        let remaining = builds.filter { $0.persistentModelID != selected.persistentModelID }
        context.delete(selected)
        if let next = remaining.first {
            Garage.select(next, in: remaining)
        }
        try? context.save()
    }
}
