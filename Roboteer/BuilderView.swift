//
//  BuilderView.swift
//  The builder. Every number on this screen comes from `Shared/parts.json`, every rule from
//  `BuildRules`, and every edit goes to the arena as `workshop_config` after 150 ms of quiet so the
//  bot on the lit stage behind the panels is always the bot you are building.
//

import SwiftUI
import SwiftData

struct BuilderView: View {

    @Bindable var host: ArenaHost
    let buildID: PersistentIdentifier

    @Environment(\.modelContext) private var context
    @State private var build: BotBuild?

    var body: some View {
        ZStack {
            StageBackdrop(host: host, still: .withBot, dim: 0.3)

            if let build {
                BuilderBody(host: host, build: build)
            } else {
                GlassPanel {
                    Text("That build is no longer in the garage.")
                        .font(Stage.label(14))
                        .foregroundStyle(Stage.text)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if build == nil {
                build = context.model(for: buildID) as? BotBuild
            }
        }
    }
}

private struct BuilderBody: View {

    @Bindable var host: ArenaHost
    @Bindable var build: BotBuild

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    enum Tab: String, CaseIterable, Hashable {
        case chassis, drive, weapon, utility, armour, livery

        var title: String {
            switch self {
            case .chassis: return "Chassis"
            case .drive: return "Drive"
            case .weapon: return "Weapon"
            case .utility: return "Utility"
            case .armour: return "Armour"
            case .livery: return "Livery"
            }
        }
    }

    @State private var tab: Tab = .chassis

    /// The career, for the blueprint locks. There is at most one and there may be none at all,
    /// which means nothing has been earned yet and only the starting unlocks can be fitted.
    @Query private var careers: [CareerState]

    private let catalogue = Catalogue.shared

    /// Every part id this player may fit (docs/stage5-spec.md section 1).
    private var unlocked: Set<String> { CareerUnlocks.held(careers.first) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(alignment: .top, spacing: 18) {
                picker
                readouts
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        // Top aligned inside the whole screen: a column taller than the screen must spill off the
        // bottom, never take the header off the top (which is what a centred ZStack child does).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            sendToStage(immediately: true)
            registerFocus()
        }
        .onChange(of: build.spec) { _, _ in
            try? context.save()
            sendToStage(immediately: false)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            StageButton("Back", kind: .quiet) { dismiss() }
                .frame(width: 96)

            TextField("Name", text: $build.name)
                .font(Stage.display(22))
                .foregroundStyle(Stage.text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .frame(width: 210)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Stage.edge, lineWidth: 1)
                }

            WeightBar(used: build.totalWeight)
                .frame(maxWidth: .infinity)

            PadHintBar(showsBack: true)
        }
    }

    /// The builder's controls are a list rather than a column of buttons, so the pad gets the two
    /// things that matter here: B goes back, and the shoulder directions walk the tabs.
    private func registerFocus() {
        PadFocus.shared.set(
            [],
            back: { dismiss() },
            sideways: { event in
                let tabs = Tab.allCases
                guard let index = tabs.firstIndex(of: tab) else { return false }
                let next = (index + (event == .left ? -1 : 1) + tabs.count) % tabs.count
                tab = tabs[next]
                return true
            }
        )
    }

    // MARK: - The picker column

    private var picker: some View {
        VStack(spacing: 10) {
            StageSegments(values: Tab.allCases, title: { $0.title }, selection: $tab)

            GlassPanel(padding: 10) {
                ScrollView {
                    VStack(spacing: 7) {
                        switch tab {
                        case .chassis: chassisRows
                        case .drive: driveRows
                        case .weapon: weaponRows
                        case .utility: utilityRows
                        case .armour: armourRows
                        case .livery: liveryRows
                        }
                    }
                    .padding(.bottom, 2)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Chassis

    private var chassisRows: some View {
        ForEach(catalogue.chassis) { chassis in
            LockGate(locked: !unlocked.contains(chassis.id), partID: chassis.id) {
            PartRow(
                name: chassis.name,
                weight: chassis.weight,
                blurb: chassis.blurb,
                selected: build.chassisID == chassis.id,
                affordable: fits(replacing: { $0.chassis = chassis.id })
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(chassisLine(chassis))
                        .font(Stage.label(11))
                        .foregroundStyle(Stage.textDim)
                    Text(chassis.invertedNote)
                        .font(Stage.body(11))
                        .foregroundStyle(Stage.textFaint)
                }
            } action: {
                build.chassisID = chassis.id
                fixWeaponIfChassisForbidsIt()
                fixSrimechIfNeeded()
            }
            }
        }
    }

    private func chassisLine(_ chassis: Catalogue.Chassis) -> String {
        let clearance = Int((chassis.clearanceFront * 1000).rounded())
        let mount: String
        switch chassis.mountWeapon {
        case "front": mount = "front mount"
        case "top": mount = "top mount"
        case "front_or_top": mount = "front or top mount"
        case "shell": mount = "shell mount"
        default: mount = chassis.mountWeapon
        }
        return "\(clearance) mm front clearance, \(mount)."
    }

    // MARK: - Drive

    private var driveRows: some View {
        ForEach(catalogue.drives) { drive in
            LockGate(locked: !unlocked.contains(drive.id), partID: drive.id) {
            PartRow(
                name: drive.name,
                weight: drive.weight,
                blurb: drive.blurb,
                selected: build.driveID == drive.id,
                affordable: fits(replacing: { $0.drive = drive.id })
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    StatPips(label: "Top speed", filled: drive.speedPips)
                    StatPips(label: "Turn", filled: drive.turnPips)
                    StatPips(label: "Push", filled: drive.pushPips)
                    Text(drive.wheelLoss.capitalizedFirst + ".")
                        .font(Stage.body(11))
                        .foregroundStyle(Stage.textFaint)
                }
            } action: {
                build.driveID = drive.id
            }
            }
        }
    }

    // MARK: - Weapon

    private var weaponRows: some View {
        ForEach(catalogue.weapons) { weapon in
            LockGate(locked: !unlocked.contains(weapon.id), partID: weapon.id) {
            PartRow(
                name: weapon.name,
                weight: weapon.weight,
                blurb: weapon.blurb,
                selected: build.weaponID == weapon.id,
                affordable: fits(replacing: { $0.weapon = weapon.id })
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    StatPips(label: "Reach", filled: weapon.reachPips)
                    StatPips(label: "Hit", filled: weapon.hitPips)
                    StatPips(label: "Setup", filled: weapon.setupPips)
                    if let note = weaponFitNote(weapon) {
                        Text(note)
                            .font(Stage.body(11))
                            .foregroundStyle(Stage.danger)
                    }
                }
            } action: {
                build.weaponID = weapon.id
                fixChassisIfWeaponDemandsIt(weapon)
            }
            }
        }
    }

    private func weaponFitNote(_ weapon: Catalogue.Weapon) -> String? {
        guard let chassis = catalogue.chassis(build.chassisID) else { return nil }
        if let allowed = chassis.weaponsAllowed, !allowed.contains(weapon.id) {
            return "Not on the \(chassis.name)."
        }
        if let required = weapon.requiresChassis, required != chassis.id {
            return "Needs the \(catalogue.chassis(required)?.name ?? required)."
        }
        return nil
    }

    // MARK: - Utility

    private var utilityRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                slot(0)
                slot(1)
            }
            ForEach(catalogue.utilities) { utility in
                let fitted = build.utilities.contains(utility.id)
                LockGate(locked: !unlocked.contains(utility.id), partID: utility.id) {
                PartRow(
                    name: utility.name,
                    weight: utility.weight,
                    blurb: utility.blurb,
                    selected: fitted,
                    affordable: fitted || fits(replacing: { spec in
                        if spec.utilities.count < 2 { spec.utilities.append(utility.id) }
                        else { spec.utilities[1] = utility.id }
                    })
                ) {
                    EmptyView()
                } action: {
                    toggle(utility.id)
                }
                }
            }
        }
    }

    private func slot(_ index: Int) -> some View {
        let id = index < build.utilities.count ? build.utilities[index] : nil
        let name = id.flatMap { catalogue.utility($0)?.name } ?? "Empty"
        return VStack(alignment: .leading, spacing: 3) {
            StageHeading("Slot \(index + 1)")
            Text(name.uppercased())
                .font(Stage.display(14))
                .kerning(0.8)
                .foregroundStyle(id == nil ? Stage.textFaint : Stage.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Stage.edge, lineWidth: 1)
        }
    }

    private func toggle(_ id: String) {
        var fitted = build.utilities
        if let index = fitted.firstIndex(of: id) {
            fitted.remove(at: index)
        } else if fitted.count < 2 {
            fitted.append(id)
        } else {
            // Both slots full: the newest fitting replaces the second slot, which is the one the
            // player chose last.
            fitted[1] = id
        }
        build.utilities = fitted
    }

    // MARK: - Armour

    private var armourRows: some View {
        VStack(spacing: 8) {
            ForEach(catalogue.faces) { face in
                armourFace(face)
            }
            HStack {
                StageHeading("Armour total")
                Spacer()
                Text(BuildRules.kilograms(BuildRules.armourWeight(build.spec)))
                    .font(Stage.numerals(13))
                    .foregroundStyle(Stage.text)
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
    }

    private func armourFace(_ face: Catalogue.Face) -> some View {
        let plate = build.spec.armour[face.id] ?? ArmourFaceSpec(material: "steel", thickness: 1)
        let weight = BuildRules.weight(ofFace: face.id, in: build.spec)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(face.name.uppercased())
                    .font(Stage.display(15))
                    .kerning(1)
                    .foregroundStyle(Stage.text)
                Text(materialNote(plate.material))
                    .font(Stage.body(10))
                    .foregroundStyle(Stage.textFaint)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(BuildRules.kilograms(weight))
                    .font(Stage.numerals(13))
                    .foregroundStyle(Stage.textDim)
            }

            StageSegments(
                values: catalogue.materials.map(\.id),
                title: { shortMaterialName($0) },
                selection: Binding(
                    get: { plate.material },
                    set: { setFace(face.id, material: $0, thickness: plate.thickness) }
                ),
                size: 11
            )

            HStack(spacing: 8) {
                StageHeading("Thickness")
                HStack(spacing: 4) {
                    ForEach(Array(catalogue.thicknessRange), id: \.self) { step in
                        Button {
                            setFace(face.id, material: plate.material, thickness: step)
                        } label: {
                            Text("\(step)")
                                .font(Stage.numerals(13))
                                .foregroundStyle(step == plate.thickness ? Color.black : Stage.textDim)
                                .frame(width: 26, height: 22)
                                .background {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(step == plate.thickness ? Color.white : Color.white.opacity(0.06))
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Stage.edge, lineWidth: 1)
        }
    }

    private func shortMaterialName(_ id: String) -> String {
        switch id {
        case "polycarbonate": return "Polycarb"
        case "titanium": return "Titanium"
        default: return catalogue.material(id)?.name ?? id
        }
    }

    private func materialNote(_ id: String) -> String {
        guard let material = catalogue.material(id) else { return "" }
        return material.summary
    }

    private func setFace(_ id: String, material: String, thickness: Int) {
        switch id {
        case "front": build.frontMaterial = material; build.frontThickness = thickness
        case "sides": build.sidesMaterial = material; build.sidesThickness = thickness
        case "rear": build.rearMaterial = material; build.rearThickness = thickness
        case "top": build.topMaterial = material; build.topThickness = thickness
        default: break
        }
    }

    // MARK: - Livery

    private var liveryRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            StageHeading("Livery")
            ForEach(LiveryPresets.all, id: \.hex) { preset in
                Button {
                    build.liveryHex = preset.hex
                } label: {
                    HStack(spacing: 12) {
                        LiverySwatch(hex: preset.hex, size: 28, selected: build.liveryHex == preset.hex)
                        Text(preset.name.uppercased())
                            .font(Stage.display(15))
                            .kerning(0.8)
                            .foregroundStyle(build.liveryHex == preset.hex ? Stage.text : Stage.textDim)
                        Spacer()
                        if build.liveryHex == preset.hex {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(Stage.text)
                        }
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(build.liveryHex == preset.hex ? 0.12 : 0.03))
                    }
                }
                .buttonStyle(.plain)
            }
            Text("Gold is reserved for scrap and winner marks, so it is not a livery.")
                .font(Stage.body(11))
                .foregroundStyle(Stage.textFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    // MARK: - Readouts

    private var readouts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)

            GlassPanel(padding: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    StageHeading(errors.isEmpty ? "Ready to fight" : "Not ready")
                    if errors.isEmpty {
                        Text("This machine passes every rule.")
                            .font(Stage.body(12))
                            .foregroundStyle(Stage.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(errors, id: \.self) { sentence in
                            Text(sentence)
                                .font(Stage.body(12))
                                .foregroundStyle(Stage.danger)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            GlassPanel(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    StageHeading("On the stage")
                    if let summary = host.workshopSummary, !summary.isEmpty {
                        if let total = summary.totalKg {
                            StageStat(label: "Assembled", value: BuildRules.kilograms(total))
                        }
                        if let clearance = summary.clearanceM {
                            StageStat(label: "Clearance", value: "\(Int((clearance * 1000).rounded())) mm")
                        }
                        if let com = summary.comHeightM {
                            StageStat(label: "Centre of mass", value: "\(Int((com * 1000).rounded())) mm")
                        }
                        // Four category rows is what fits under the three totals at 402 pt tall.
                        ForEach(summary.categories.prefix(4), id: \.self) { key in
                            StageStat(
                                label: key.replacingOccurrences(of: "_", with: " "),
                                value: BuildRules.kilograms(summary.categoryWeights[key] ?? 0)
                            )
                        }
                    } else {
                        StageStat(label: "Parts", value: BuildRules.kilograms(BuildRules.partsWeight(build.spec)))
                        StageStat(label: "Armour", value: BuildRules.kilograms(BuildRules.armourWeight(build.spec)))
                        Text(host.arenaReady
                             ? "Waiting for the arena to assemble it."
                             : "The arena reports its own numbers once it is running.")
                            .font(Stage.body(11))
                            .foregroundStyle(Stage.textFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(width: 250)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    /// Three sentences is all the panel has room for at 402 pt tall, and a build with four
    /// problems has the same first fix as a build with three.
    private var errors: [String] { Array(BuildRules.errors(build.spec).prefix(3)) }

    // MARK: - Keeping the build legal

    /// Would the build still fit the budget with this one change?
    private func fits(replacing change: (inout BuildSpec) -> Void) -> Bool {
        var candidate = build.spec
        change(&candidate)
        return BuildRules.totalWeight(candidate) <= BuildRules.budget + 0.0001
    }

    /// The Shell only takes certain weapons, so changing to it changes the weapon too rather than
    /// leaving the player with an error they did not ask for.
    private func fixWeaponIfChassisForbidsIt() {
        guard let chassis = catalogue.chassis(build.chassisID),
              let allowed = chassis.weaponsAllowed,
              !allowed.contains(build.weaponID),
              let first = allowed.first else { return }
        build.weaponID = first
    }

    /// A full body spinner needs the Shell.
    private func fixChassisIfWeaponDemandsIt(_ weapon: Catalogue.Weapon) {
        guard let required = weapon.requiresChassis, required != build.chassisID else { return }
        build.chassisID = required
        fixSrimechIfNeeded()
    }

    /// An invertible chassis frees the srimech slot; a chassis that needs one gets one.
    private func fixSrimechIfNeeded() {
        guard let chassis = catalogue.chassis(build.chassisID) else { return }
        var fitted = build.utilities
        if chassis.srimechRequired, !fitted.contains("srimech") {
            if fitted.count < 2 {
                fitted.insert("srimech", at: 0)
            } else {
                fitted[0] = "srimech"
            }
            build.utilities = fitted
        }
    }

    // MARK: - The stage

    private func sendToStage(immediately: Bool) {
        guard host.surface == .stage else { return }
        let config = build.toBotConfig(id: FightConfigFixture.playerID, controller: "player")
        if immediately {
            host.sendWorkshopConfig(config)
        } else {
            host.sendWorkshopConfigDebounced(config)
        }
    }
}
