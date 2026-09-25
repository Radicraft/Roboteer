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
            StageBackdrop(host: host, still: .withBot, dim: 0.2)

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

    /// `-builderTab <name>` opens the builder on that tab (docs/qa-launch-flags.md), so a
    /// headless screenshot can be taken of a picker that is five taps in. Anything the enum
    /// does not recognise, including no flag at all, is the chassis tab a player starts on.
    @State private var tab: Tab = Tab(rawValue: ArenaHost.launchArgument("-builderTab") ?? "") ?? .chassis

    /// One `workshop_config` per 150 ms of quiet while the player edits.
    @State private var stageDebounce: DispatchWorkItem?

    /// The career, for the blueprint locks. There is at most one and there may be none at all,
    /// which means nothing has been earned yet and only the starting unlocks can be fitted.
    @Query private var careers: [CareerState]

    private let catalogue = Catalogue.shared

    /// Every part id this player may fit (docs/stage5-spec.md section 1).
    private var unlocked: Set<String> { CareerUnlocks.held(careers.first) }

    private static let gutter: CGFloat = 26

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 10) {
                header
                HStack(spacing: 0) {
                    // The machine being built stands here, live. It is the only reason to look at
                    // this screen, so no panel is allowed over it, and dragging it turns it.
                    StageOrbitPad(host: host) { markOrbited() }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    column
                        .frame(width: StageLayout.columnWidth(proxy.size.width - 2 * Self.gutter))
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, Self.gutter)
            .padding(.vertical, 14)
            // Top aligned inside the whole screen: a column taller than the screen must spill off
            // the bottom, never take the header off the top (which is what a centred ZStack child
            // does).
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay(alignment: .bottomLeading) { orbitHint }
        .onAppear {
            sendToStage(immediately: true)
            registerFocus()
        }
        .onChange(of: build.spec) { _, _ in
            try? context.save()
            sendToStage(immediately: false)
        }
    }

    // MARK: - The turntable hint

    /// The stage takes touches now (`GodotSurface`), so the turntable of brief section 11 finally
    /// works. One faint line says so, once: it goes for good the first time the player drags.
    @State private var hasOrbited = UserDefaults.standard.bool(forKey: "stage.hasOrbited")

    @ViewBuilder
    private var orbitHint: some View {
        if !hasOrbited {
            Text("DRAG TO TURN  \u{00B7}  PINCH TO ZOOM")
                .font(Stage.label(11, weight: .bold))
                .kerning(1.4)
                .foregroundStyle(Stage.textFaint)
                .shadow(color: .black.opacity(0.8), radius: 6, y: 1)
                .padding(.leading, Self.gutter + 2)
                .padding(.bottom, 14)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transition(.opacity)
        }
    }

    private func markOrbited() {
        guard !hasOrbited else { return }
        withAnimation(.easeOut(duration: 0.25)) { hasOrbited = true }
        UserDefaults.standard.set(true, forKey: "stage.hasOrbited")
    }

    // MARK: - The right hand column

    /// Segments, the compact readout strip, then the part list. Everything the builder needs is in
    /// this one column so the left of the screen is the machine.
    private var column: some View {
        VStack(spacing: 8) {
            StageSegments(values: Tab.allCases, title: { $0.title }, selection: $tab)
            readoutStrip
            picker
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                    CutRect(8)
                        .fill(Stage.type.opacity(0.07))
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
                        .font(Stage.body(13))
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
                        .font(Stage.body(13))
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
                affordable: fits(replacing: { $0.weapon = weapon.id }),
                glyph: BroadcastGlyph.weapon(weapon.id)
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    StatPips(label: "Reach", filled: weapon.reachPips)
                    StatPips(label: "Hit", filled: weapon.hitPips)
                    StatPips(label: "Setup", filled: weapon.setupPips)
                    if let note = weaponFitNote(weapon) {
                        Text(note)
                            .font(Stage.body(13))
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
                    }),
                    glyph: BroadcastGlyph.utility(utility.id)
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
            CutRect(9)
                .fill(Stage.type.opacity(0.05))
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
            if !lockedMaterialsNote.isEmpty {
                Text(lockedMaterialsNote)
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
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
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.textFaint)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(BuildRules.kilograms(weight))
                    .font(Stage.numerals(13))
                    .foregroundStyle(Stage.textDim)
            }

            // Bug 3: a material is a part like any other. One the player does not own is locked
            // here exactly as the chassis, drive, weapon and utility rows are, and the note above
            // the faces says what opens it. Three to a row, so no name is cut short.
            StageSegments(
                values: catalogue.materials.map(\.id),
                title: { shortMaterialName($0) },
                selection: Binding(
                    get: { plate.material },
                    set: { setFace(face.id, material: $0, thickness: plate.thickness) }
                ),
                size: 11,
                isEnabled: { unlocked.contains($0) },
                perRow: 3
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
                                .foregroundStyle(step == plate.thickness ? Stage.type : Stage.textDim)
                                .frame(width: 26, height: 22)
                                .background {
                                    CutRect(6)
                                        .fill(step == plate.thickness ? Stage.line.opacity(0.22) : Stage.type.opacity(0.05))
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
            CutRect(10)
                .fill(Stage.type.opacity(0.04))
        }
    }

    /// "Locked: Reinforced steel (level 10 in the shop), Reactive armour (unlocks with the full
    /// game)." One line for the
    /// whole tab rather than one per face.
    private var lockedMaterialsNote: String {
        let locked = catalogue.materials.map(\.id).filter { !unlocked.contains($0) }
        guard !locked.isEmpty else { return "" }
        let parts = locked.map { id -> String in
            var note = CareerUnlocks.lockNote(for: id)
            while note.hasSuffix(".") { note.removeLast() }
            if let first = note.first { note = first.lowercased() + note.dropFirst() }
            return "\(catalogue.material(id)?.name ?? id) (\(note))"
        }
        return "Locked: " + parts.joined(separator: ", ") + "."
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
            // QA only (docs/qa-launch-flags.md `-builderPaint`): the paint wall sits under
            // six colour rows, so on a phone it is one scroll down and a headless
            // screenshot cannot reach it. This shows the wall on its own and changes
            // nothing a player sees. Same idea as B1's post-match fixture branch.
            if !ArenaHost.hasLaunchFlag("-builderPaint") {
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
                        CutRect(10)
                            .fill(Stage.type.opacity(build.liveryHex == preset.hex ? 0.12 : 0.03))
                    }
                }
                .buttonStyle(.plain)
            }
            Text("Gold is reserved for scrap and winner marks, so it is not a livery.")
                .font(Stage.body(13))
                .foregroundStyle(Stage.textFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            }

            paintRows
        }
    }

    // MARK: - Paint

    /// The Level this player has reached, which is what opens a paint job. No career at all
    /// means nothing has been earned yet, so only PLAIN is offered and the rest say which
    /// Level they arrive at (brief v5 section 7).
    private var level: Int { careers.first?.level ?? 0 }

    /// Paint is free, cosmetic and Level gated, so the picker is a wall of previews rather
    /// than a list of rows: the pattern is the only thing a player is choosing between, and
    /// the name is what they read after they have seen it. A locked one is shown, dimmed,
    /// with the Level it arrives at, because a milestone you can see coming is the reward.
    private var paintRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            StageHeading("Paint")
            // Four across: eleven tiles land in three rows, which is what makes the wall
            // read as a wall rather than as a list that happens to have pictures in it.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                      spacing: 6) {
                PaintTile(job: nil, selected: build.paintID == nil, level: level) {
                    build.paintID = nil
                    sendToStage(immediately: true)
                }
                ForEach(PaintJobs.unlocked(at: level)) { job in
                    PaintTile(job: job,
                              selected: build.paintID == job.id,
                              level: level) {
                        build.paintID = job.id
                        sendToStage(immediately: true)
                    }
                }
            }
            Text(paintNote)
                .font(Stage.body(13))
                .foregroundStyle(Stage.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
        .onAppear {
            // A paint job the player can no longer wear comes off. That is a catalogue
            // rebalance or a save from a build with more art in it than this one, and
            // either way the machine has to stop claiming it.
            if build.paintID != nil, PaintJobs.fitted(build.paintID, at: level) == nil {
                build.paintID = nil
                sendToStage(immediately: true)
            }
            // QA only (docs/qa-launch-flags.md `-builderPaintJob <id>`): fit a paint job on
            // entry so a phone pass does not need a thumb. No flag, nothing happens.
            guard let id = ArenaHost.launchArgument("-builderPaintJob"),
                  PaintJobs.fitted(id, at: level) != nil, build.paintID != id else { return }
            build.paintID = id
            sendToStage(immediately: true)
        }
    }

    private var paintNote: String {
        if let id = build.paintID, let job = PaintJobs.unlocked(at: level).first(where: { $0.id == id }) {
            return "\(job.name). Paint is cosmetic and changes nothing about a fight."
        }
        let next = PaintJobs.list.first { $0.level > level }
        guard let next else { return "Every paint job is open to you." }
        return "The next paint job arrives at Level \(next.level). They are free and cosmetic."
    }

    // MARK: - Readouts

    /// Everything the old right hand column of panels said, in one strip under the tabs.
    ///
    /// Weight already lives in the header, so the strip carries the two or three numbers that move
    /// when a part is picked, and the one sentence that says whether the machine is legal. The
    /// arena's own measurements (what it assembled, the centre of mass, the weight per category)
    /// are behind the chevron, because they are for a player who goes looking.
    @State private var showsArenaNumbers = false

    private var readoutStrip: some View {
        GlassPanel(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    figure("Parts", BuildRules.kilograms(BuildRules.partsWeight(build.spec)))
                    strut
                    figure("Armour", BuildRules.kilograms(BuildRules.armourWeight(build.spec)))
                    strut
                    figure(thirdFigure.0, thirdFigure.1)
                    Spacer(minLength: 0)
                    Button {
                        showsArenaNumbers.toggle()
                    } label: {
                        Image(systemName: showsArenaNumbers ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(Stage.textFaint)
                            .frame(width: 22, height: 18)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showsArenaNumbers ? "Hide the arena's numbers" : "Show the arena's numbers")
                }

                if let first = errors.first {
                    Text(first)
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.danger)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("This machine passes every rule.")
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.textFaint)
                        .lineLimit(1)
                }

                if showsArenaNumbers {
                    HairRule()
                    arenaNumbers
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(Stage.label(11, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(Stage.textFaint)
            Text(value)
                .font(Stage.numerals(14))
                .foregroundStyle(Stage.text)
                .lineLimit(1)
                .minimumScaleFactor(BroadcastType.floorScale(.numerals, size: 14, wanted: 0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
    }

    private var strut: some View {
        Rectangle()
            .fill(Stage.edge)
            .frame(width: 1, height: 22)
    }

    /// The third number is whatever the arena can tell us about the machine it built; before it has
    /// built one it is the drive's top speed, which is the other number a pick moves.
    private var thirdFigure: (String, String) {
        if let clearance = host.workshopSummary?.clearanceM {
            return ("Clearance", "\(Int((clearance * 1000).rounded())) mm")
        }
        if let drive = catalogue.drive(build.driveID) {
            return ("Speed", "\(drive.speedPips) of 5")
        }
        return ("Armour faces", "\(build.spec.armour.count)")
    }

    @ViewBuilder
    private var arenaNumbers: some View {
        if let summary = host.workshopSummary, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if let total = summary.totalKg {
                    StageStat(label: "Assembled", value: BuildRules.kilograms(total))
                }
                if let com = summary.comHeightM {
                    StageStat(label: "Centre of mass", value: "\(Int((com * 1000).rounded())) mm")
                }
                ForEach(summary.categories.prefix(4), id: \.self) { key in
                    StageStat(
                        label: key.replacingOccurrences(of: "_", with: " "),
                        value: BuildRules.kilograms(summary.categoryWeights[key] ?? 0)
                    )
                }
            }
        } else {
            Text(host.arenaReady
                 ? "Waiting for the arena to assemble it."
                 : "The arena reports its own numbers once it is running.")
                .font(Stage.body(13))
                .foregroundStyle(Stage.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    /// Still one send per 150 ms of quiet, so dragging a stepper does not flood the bridge
    /// (docs/stage4-spec.md section 7). The debounce is here rather than `ArenaHost`'s own because
    /// the host's convenience drops the framing, and the framing is the whole fix: the machine has
    /// to stand left of this screen's column, not behind it.
    private func sendToStage(immediately: Bool) {
        guard host.surface == .stage else { return }
        let config = build.toBotConfig(id: FightConfigFixture.playerID, controller: "player")
        stageDebounce?.cancel()
        stageDebounce = nil
        guard !immediately else {
            host.sendWorkshopConfig(config, frame: StageLayout.botFrame)
            return
        }
        let work = DispatchWorkItem {
            host.sendWorkshopConfig(config, frame: StageLayout.botFrame)
        }
        stageDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
