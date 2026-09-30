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
            StageBackdrop(host: host, still: .withBot, dim: 0, shade: .right)

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

    /// Wave D: the tale of the tape lines sheet. `-builderTape` (with `-autoBuilder`) opens it, for
    /// screenshots.
    @State private var showsTape = ArenaHost.hasLaunchFlag("-builderTape")

    /// The career, for the blueprint locks. There is at most one and there may be none at all,
    /// which means nothing has been earned yet and only the starting unlocks can be fitted.
    @Query private var careers: [CareerState]

    private let catalogue = Catalogue.shared

    /// Every part id this player may fit (docs/stage5-spec.md section 1).
    private var unlocked: Set<String> { CareerUnlocks.held(careers.first) }

    private static let gutter: CGFloat = 0

    /// Where the builder's plates are, so the leader tags keep clear of them.
    @State private var keepOut = LeaderKeepOut()

    /// Wave C, direction A: the part being looked at in the list, before it is fitted. Nil is
    /// "the fitted one". Chosen with a tap, fitted with the primary under the plate, the way the
    /// approved builder reads ("Fit the axe, +2.0 kg").
    @State private var looking: String?

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 400
            ZStack(alignment: .topLeading) {
                StageLeaderLayer(anchors: host.stageAnchors, screen: "builder",
                                 leaders: builderLeaders, keepOut: keepOut)
                HStack(alignment: .top, spacing: 16) {
                    // The machine being built stands here, live. It is the only reason to look at
                    // this screen, so no panel is allowed over it, and dragging it turns it.
                    ZStack(alignment: .topLeading) {
                        StageOrbitPad(host: host) { markOrbited() }
                        header
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    column(compact: compact)
                        .frame(width: min(346, (proxy.size.width * 0.415).rounded()))
                }
                .padding(.top, compact ? 12 : 16)
                .padding(.bottom, compact ? 4 : 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay(alignment: .bottomLeading) { orbitHint }
        .sheet(isPresented: $showsTape) { TapeLinesSheet(build: build) }
        .onAppear {
            sendToStage(immediately: true)
            registerFocus()
        }
        .onChange(of: build.spec) { _, _ in
            try? context.save()
            sendToStage(immediately: false)
        }
        .onChange(of: tab) { _, _ in
            looking = nil
            sendToStage(immediately: true)
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
                // A leader tag must not sit on the hint (874 x 402, 2026-09-30).
                .leaderKeepOut(keepOut, "hint")
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

    /// One plate: the tabs, the mass gauge, the part list and the numbers of the part being looked
    /// at; the primary under it. Everything the builder needs is in this column so the left of the
    /// screen is the machine.
    private func column(compact: Bool) -> some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                StageSegments(values: Tab.allCases, title: { $0.title }, selection: $tab)
                    .padding(.bottom, 10)
                BlueprintMassGauge(used: build.totalWeight, adding: addingKg)
                if let first = errors.first, !(overweight && errors.count == 1) {
                    Text(first)
                        .font(Blueprint.body(13))
                        .foregroundStyle(Blueprint.danger)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                picker
                    .padding(.top, 8)
                footer
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .blueprintPlate()
            .leaderKeepOut(keepOut, "plate")

            primary
                .leaderKeepOut(keepOut, "primary")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header

    /// The Back plate and the machine's name in stencil, which is still the field that renames it.
    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            BackChevron { dismiss() }
            TextField("Name", text: $build.name)
                .font(Blueprint.display(28))
                .foregroundStyle(Color.white)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 1)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .frame(maxWidth: 260)

            // Wave D walk-outs: the player's own strength and weakness lines (TapeLinesSheet).
            TextLink("Tale of the tape", tint: Stage.line, size: 12) { showsTape = true }
                .fixedSize()

            PadHintBar(showsBack: true)
        }
        .leaderKeepOut(keepOut, "header")
    }

    // MARK: - Looking and fitting

    /// The part id fitted in the current tab's slot (the first free utility slot's worth for the
    /// utility tab is nil).
    private var fittedID: String? {
        switch tab {
        case .chassis: return build.chassisID
        case .drive: return build.driveID
        case .weapon: return build.weaponID
        default: return nil
        }
    }

    /// The row lit in the list: the one being looked at, or the fitted one.
    private var lookedAt: String? { looking ?? fittedID }

    /// True when the part being looked at is a change to the machine.
    private var hasPick: Bool {
        guard let looking else { return false }
        if tab == .utility { return true }
        return looking != fittedID
    }

    /// What fitting the part being looked at would do to the build.
    private func candidate() -> BuildSpec? {
        guard hasPick, let looking else { return nil }
        var spec = build.spec
        switch tab {
        case .chassis: spec.chassis = looking
        case .drive: spec.drive = looking
        case .weapon: spec.weapon = looking
        case .utility:
            if let index = spec.utilities.firstIndex(of: looking) {
                spec.utilities.remove(at: index)
            } else if spec.utilities.count < 2 {
                spec.utilities.append(looking)
            } else {
                spec.utilities[1] = looking
            }
        default: return nil
        }
        return spec
    }

    /// Kilograms the pick adds (negative takes weight off).
    private var addingKg: Double {
        guard let spec = candidate() else { return 0 }
        return BuildRules.totalWeight(spec) - build.totalWeight
    }

    private var overweight: Bool { build.totalWeight > BuildRules.budget + 0.0001 }

    private func signedKg(_ value: Double) -> String {
        value >= 0 ? "+\(BuildRules.kilograms(value))" : "-\(BuildRules.kilograms(-value))"
    }

    /// The name of a part in any of the four list tabs.
    private func partName(_ id: String) -> String {
        switch tab {
        case .chassis: return catalogue.chassis(id)?.name ?? id
        case .drive: return catalogue.drive(id)?.name ?? id
        case .weapon: return catalogue.weapon(id)?.name ?? id
        case .utility: return catalogue.utility(id)?.name ?? id
        default: return id
        }
    }

    /// The one primary: fit the part being looked at, or say why it cannot go on, or DONE.
    @ViewBuilder
    private var primary: some View {
        if hasPick, let looking, let spec = candidate() {
            let removing = tab == .utility && build.utilities.contains(looking)
            let total = BuildRules.totalWeight(spec)
            if total > BuildRules.budget + 0.0001 {
                primaryPlate(title: "Over by", note: BuildRules.kilograms(total - BuildRules.budget), enabled: false) {}
            } else {
                primaryPlate(title: removing ? "Take off the \(partName(looking).lowercased())"
                                             : "Fit the \(partName(looking).lowercased())",
                             note: signedKg(total - build.totalWeight), enabled: true) {
                    fit(looking)
                }
            }
        } else if overweight {
            primaryPlate(title: "Over by", note: BuildRules.kilograms(build.totalWeight - BuildRules.budget), enabled: false) {}
        } else {
            primaryPlate(title: "Done", note: BuildRules.kilograms(build.totalWeight), enabled: true) {
                dismiss()
            }
        }
    }

    private func primaryPlate(title: String, note: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { if enabled { action() } }) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(note)
                    .font(Blueprint.mono(13))
                    .opacity(0.65)
            }
        }
        .buttonStyle(BroadcastButtonStyle(kind: .primary, enabled: enabled,
                                          focused: PadFocus.shared.isFocused("builder.primary")))
        .disabled(!enabled)
        .accessibilityLabel("\(title) \(note)")
    }

    /// The primary, from a pad: whatever the plate says.
    private func activatePrimary() {
        if hasPick, let looking, let spec = candidate() {
            if BuildRules.totalWeight(spec) <= BuildRules.budget + 0.0001 { fit(looking) }
        } else if !overweight {
            dismiss()
        }
    }

    /// Fit the part being looked at, with the same fixes the old one tap fitting made.
    private func fit(_ id: String) {
        switch tab {
        case .chassis:
            build.chassisID = id
            fixWeaponIfChassisForbidsIt()
            fixSrimechIfNeeded()
        case .drive:
            build.driveID = id
        case .weapon:
            build.weaponID = id
            if let weapon = catalogue.weapon(id) { fixChassisIfWeaponDemandsIt(weapon) }
        case .utility:
            toggle(id)
        default:
            break
        }
        looking = nil
    }

    /// Tap a row: look at it. Tap the row being looked at again: fit it, as the old list did.
    private func look(_ id: String) {
        if looking == id, hasPick, let spec = candidate(),
           BuildRules.totalWeight(spec) <= BuildRules.budget + 0.0001 {
            fit(id)
        } else {
            looking = (id == fittedID && tab != .utility) ? nil : id
        }
    }

    /// The short word on a row the player may not fit yet: the Level, the full game, or the
    /// shop's price.
    private func lockWord(_ id: String) -> String {
        if Gates.snapshot.lockedReasonIfLocked(.part(id)) != nil { return "Full game" }
        let level = ProgressionEngine.levelRequired(id)
        if level > (careers.first?.level ?? 1) { return "Level \(level)" }
        let price = ProgressionEngine.price(id)
        return price > 0 ? "Shop, \(price)" : "In the shop"
    }

    /// Direction A's row for one part in a list tab.
    private func partRow(id: String, name: String, weight: Double, note: String, glyph: GlyphArt?) -> some View {
        let locked = !unlocked.contains(id)
        let fitted = tab == .utility ? build.utilities.contains(id) : id == fittedID
        let state: BlueprintPartRow<AnyView>.State =
            locked ? .locked : (looking == id ? .selected : (fitted ? .fitted : .normal))
        let shownNote = locked ? lockWord(id) : (fitted ? "Fitted" : note)
        return BlueprintPartRow(glyph: glyph, name: name, note: shownNote, state: state) {
            AnyView(Text(BuildRules.kilograms(weight))
                .font(Blueprint.mono(12)).kerning(Blueprint.monoKern(12))
                .foregroundStyle(Color.white)
                .frame(width: 48, alignment: .trailing))
        } action: {
            guard !locked else { return }
            look(id)
        }
        .allowsHitTesting(!locked)
        .accessibilityHint(locked ? CareerUnlocks.lockNote(for: id) : "")
        .id(id)
    }

    /// Under the list: the numbers of the part being looked at, as the approved builder shows them.
    @ViewBuilder
    private var footer: some View {
        let stats = footerStats
        if !stats.isEmpty {
            VStack(spacing: 0) {
                BlueprintRule()
                HStack(alignment: .top, spacing: 16) {
                    ForEach(stats, id: \.0) { stat in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(stat.0).font(Blueprint.ui(11.5)).foregroundStyle(Blueprint.dim)
                            Text(stat.1)
                                .font(Stage.figure(stat.1, size: 17.5))
                                .kerning(BroadcastType.isFigure(stat.1) ? Blueprint.monoKern(14) : 0)
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
            }
            .padding(.top, 8)
        }
    }

    private var footerStats: [(String, String)] {
        guard let id = lookedAt else { return [] }
        switch tab {
        case .weapon:
            guard let weapon = catalogue.weapon(id) else { return [] }
            var out = [("Reach", "\(Int((weapon.reach * 1000).rounded())) mm"),
                       ("Hit", "\(weapon.hitPips) of 5")]
            if weapon.setupSeconds > 0 {
                out.append(("Reset", String(format: "%.1f s", weapon.setupSeconds)))
            }
            out.append(("Mass", BuildRules.kilograms(weapon.weight)))
            return out
        case .drive:
            guard let drive = catalogue.drive(id) else { return [] }
            return [("Speed", "\(drive.speedPips) of 5"), ("Turn", "\(drive.turnPips) of 5"),
                    ("Push", "\(drive.pushPips) of 5"), ("Mass", BuildRules.kilograms(drive.weight))]
        case .chassis:
            guard let chassis = catalogue.chassis(id) else { return [] }
            return [("Clearance", "\(Int((chassis.clearanceFront * 1000).rounded())) mm"),
                    ("Mount", mountWord(chassis.mountWeapon)),
                    ("Mass", BuildRules.kilograms(chassis.weight))]
        default:
            return []
        }
    }

    private func mountWord(_ mount: String) -> String {
        switch mount {
        case "front": return "Front"
        case "top": return "Top"
        case "front_or_top": return "Front or top"
        case "shell": return "Shell"
        default: return mount.capitalized
        }
    }

    // MARK: - The leaders

    /// The focused category's part, and the top armour, named from the build.
    private var builderLeaders: [Leader] {
        var out: [Leader] = []
        let pickLine: String? = {
            guard hasPick, let looking else { return nil }
            if tab == .utility, build.utilities.contains(looking) {
                return "\(partName(looking)) off, \(signedKg(addingKg))"
            }
            return "\(partName(looking)) in, \(signedKg(addingKg))"
        }()
        switch tab {
        case .weapon:
            let mount = mountWord(catalogue.chassis(build.chassisID)?.mountWeapon ?? "front")
            out.append(Leader(id: "focus", target: .partOrPoint("weapon", "weapon"),
                              title: "\(mount) mount",
                              value: pickLine ?? "\(catalogue.weapon(build.weaponID)?.name ?? "Weapon") fitted",
                              dx: 70, dy: 110))
        case .drive:
            out.append(Leader(id: "focus", target: .kind("wheel", prefer: ["wheel_fl", "wheel_rl", "track_l"]),
                              title: "Drive",
                              value: pickLine ?? "\(catalogue.drive(build.driveID)?.name ?? "Drive") fitted",
                              dx: 60, dy: 100))
        case .chassis:
            out.append(Leader(id: "focus", target: .partOrPoint("chassis", "centre"),
                              title: "Hull",
                              value: pickLine ?? "\(catalogue.chassis(build.chassisID)?.name ?? "Hull") fitted",
                              dx: 70, dy: 110))
        case .utility:
            out.append(Leader(id: "focus", target: .partOrPoint("utility", "centre"),
                              title: "Utility",
                              value: pickLine ?? (build.utilities.isEmpty ? "Both slots free"
                                                  : build.utilities.compactMap { catalogue.utility($0)?.name }.joined(separator: ", ")),
                              dx: 70, dy: 110))
        case .armour:
            out.append(Leader(id: "focus", target: .kind("armour", prefer: ["armour_front", "armour_sides"]),
                              title: "Front armour",
                              value: BuildRules.kilograms(BuildRules.weight(ofFace: "front", in: build.spec)),
                              dx: 70, dy: 110))
        case .livery:
            break
        }
        let material = catalogue.material(build.topMaterial)?.name ?? build.topMaterial.capitalized
        out.append(Leader(id: "top", target: .partOrPoint("armour_top", "top"),
                          title: "\(material) top",
                          value: build.topThickness == 1 ? "1 unit" : "\(build.topThickness) units",
                          dx: -50, dy: -51))
        return out
    }

    /// The builder's controls are a list rather than a column of buttons, so the pad gets the two
    /// things that matter here: B goes back, and the shoulder directions walk the tabs.
    private func registerFocus() {
        PadFocus.shared.set(
            [PadItem("builder.primary") { activatePrimary() }],
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
        VStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 0) {
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
                .frame(maxHeight: .infinity, alignment: .top)
                // The fitted part is the one the player came for: bring it into view.
                .onAppear { if let id = fittedID { reader.scrollTo(id, anchor: .center) } }
                .onChange(of: tab) { _, _ in
                    if let id = fittedID { reader.scrollTo(id, anchor: .center) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Chassis

    private var chassisRows: some View {
        ForEach(Array(catalogue.chassis.enumerated()), id: \.element.id) { index, chassis in
            if index > 0 { BlueprintRule() }
            partRow(id: chassis.id, name: chassis.name, weight: chassis.weight,
                    note: "\(mountWord(chassis.mountWeapon)) mount", glyph: nil)
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
        ForEach(Array(catalogue.drives.enumerated()), id: \.element.id) { index, drive in
            if index > 0 { BlueprintRule() }
            partRow(id: drive.id, name: drive.name, weight: drive.weight,
                    note: drive.tracks > 0 ? "Tracks" : "\(drive.wheels) wheels", glyph: nil)
        }
    }

    // MARK: - Weapon

    private var weaponRows: some View {
        ForEach(Array(catalogue.weapons.enumerated()), id: \.element.id) { index, weapon in
            if index > 0 { BlueprintRule() }
            partRow(id: weapon.id, name: weapon.name, weight: weapon.weight,
                    note: weaponFitNote(weapon) ?? "Reach \(Int((weapon.reach * 1000).rounded()))",
                    glyph: BroadcastGlyph.weapon(weapon.id))
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                slot(0)
                slot(1)
            }
            .padding(.bottom, 6)
            ForEach(Array(catalogue.utilities.enumerated()), id: \.element.id) { index, utility in
                if index > 0 { BlueprintRule() }
                partRow(id: utility.id, name: utility.name, weight: utility.weight,
                        note: "", glyph: BroadcastGlyph.utility(utility.id))
            }
        }
    }

    private func slot(_ index: Int) -> some View {
        let id = index < build.utilities.count ? build.utilities[index] : nil
        let name = id.flatMap { catalogue.utility($0)?.name } ?? "Empty"
        return VStack(alignment: .leading, spacing: 3) {
            StageHeading("Slot \(index + 1)")
            Text(name)
                .font(Blueprint.ui(15))
                .foregroundStyle(id == nil ? Stage.textFaint : Stage.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background { Rectangle().fill(Blueprint.tabOff) }
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
        let focus = tab == .livery ? "paint" : tab.rawValue
        guard !immediately else {
            host.sendWorkshopConfig(config, frame: StageLayout.botFrame, screen: "builder", focus: focus)
            return
        }
        let work = DispatchWorkItem {
            host.sendWorkshopConfig(config, frame: StageLayout.botFrame, screen: "builder", focus: focus)
        }
        stageDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
