//
//  QuickFight.swift
//  The three questions a quick fight asks before it starts: where, who, and how many.
//
//  It is deliberately small. The career picks its own arena and its own opponent, so this is the
//  only screen in the game where the player chooses those, and the choice is remembered so the
//  second quick fight is one press.
//
//  The locked arenas are shown, not hidden: a locked thing is always visible and always readable
//  (docs/stage6-spec.md, `Gates`), so the four behind the wall sit there greyed with the reason.
//

import SwiftUI
import SwiftData

// MARK: - The choice

struct QuickFightChoice: Equatable {

    var arenaID: String = "yard"
    /// A rival's catalogue id, or empty for a made up entrant at the player's own tier.
    var rivalID: String = ""
    /// Three machines, last one still moving wins.
    var rumble: Bool = false
    /// The house bot on duty (brief v4 section 3), or nil while the player has never said.
    /// Unset means the tier decides: on from Regional up, off at Scrapyard, where the corner
    /// is something to be taught rather than something to lose to.
    var houseBot: Bool? = nil

    var isFiller: Bool { rivalID.isEmpty }

    /// Is there a house bot in this quick fight? A rumble never has one: three machines and a
    /// house bot is four, and the rumble rules are untouched by brief v4 (section 10 item 3).
    func houseBotOn(tier: CareerTier) -> Bool {
        if rumble { return false }
        return houseBot ?? (tier != .scrapyard)
    }

    // MARK: Remembering it

    private enum Key {
        static let arena = "quickFight.arena"
        static let rival = "quickFight.rival"
        static let rumble = "quickFight.rumble"
        static let houseBot = "quickFight.houseBot"
    }

    /// The last choice, as far as it is still allowed: a locked arena falls back to The Yard, so
    /// a player who tried the full game and then lost the entitlement is never stuck.
    static func remembered(gates: Gates) -> QuickFightChoice {
        let defaults = UserDefaults.standard
        var choice = QuickFightChoice()
        if let arena = defaults.string(forKey: Key.arena),
           Catalogue.shared.arena(arena) != nil,
           gates.arenaAvailable(arena) {
            choice.arenaID = arena
        }
        if let rival = defaults.string(forKey: Key.rival),
           CareerCatalogue.shared.rival(rival) != nil {
            choice.rivalID = rival
        }
        choice.rumble = defaults.bool(forKey: Key.rumble)
        // Left unset until the player has actually moved the switch, so the tier's own default
        // keeps applying to a player who has never thought about it.
        if defaults.object(forKey: Key.houseBot) != nil {
            choice.houseBot = defaults.bool(forKey: Key.houseBot)
        }
        return choice
    }

    func remember() {
        let defaults = UserDefaults.standard
        defaults.set(arenaID, forKey: Key.arena)
        defaults.set(rivalID, forKey: Key.rival)
        defaults.set(rumble, forKey: Key.rumble)
        if let houseBot {
            defaults.set(houseBot, forKey: Key.houseBot)
        }
    }
}

// MARK: - Who you are fighting

enum QuickFight {

    static let playerID = FightConfigFixture.playerID
    static let firstOpponentID = "ai-1"
    static let secondOpponentID = "ai-2"

    /// The opponent the choice names: a rival at the player's own tier, or a machine made up for
    /// this fight at that tier's power band.
    static func opponent(for choice: QuickFightChoice, tier: CareerTier, seed: Int) -> CareerEntrant {
        if !choice.rivalID.isEmpty, let rival = CareerCatalogue.shared.rival(choice.rivalID) {
            return CareerEntrant(
                id: firstOpponentID,
                name: rival.name,
                roboteer: rival.roboteer,
                liveryHex: rival.liveryHex,
                kind: .rival,
                spec: CareerEngine.rivalSpec(rival, at: tier),
                rivalID: rival.id
            )
        }
        return filler(tier: tier, index: 0, seed: seed)
    }

    /// A filler entrant, made fresh for this fight. The seed comes from the choice and the clock,
    /// so two quick fights in a row are not the same machine twice.
    static func filler(tier: CareerTier, index: Int, seed: Int) -> CareerEntrant {
        var rng = SeededRandom(seed: seed &+ index &* 7919)
        return CareerEngine.fillerEntrant(index: index, tier: tier, rng: &rng)
    }

    /// The bot configurations to put in `bots` after the player, ready for the bridge.
    static func opponentConfigs(
        for choice: QuickFightChoice,
        tier: CareerTier,
        seed: Int
    ) -> [[String: Any]] {
        var configs = [opponent(for: choice, tier: tier, seed: seed).spec
            .toBotConfig(id: firstOpponentID, controller: "ai")]
        if choice.rumble {
            // The third machine is always a filler: a rumble is the player, their pick, and the
            // yard's opinion of both of them.
            configs.append(filler(tier: tier, index: 3, seed: seed &+ 104_729).spec
                .toBotConfig(id: secondOpponentID, controller: "ai"))
        }
        return configs
    }

    /// The house bot on duty in this quick fight, or nil when there is none: the boss is the one
    /// the tier and the chosen arena name (brief v4 section 3), so a quick fight in the Furnace
    /// meets the machine a career fight there would meet.
    static func houseBot(for choice: QuickFightChoice, tier: CareerTier)
        -> (id: String, speed: Double)? {
        guard choice.houseBotOn(tier: tier) else { return nil }
        return CareerEngine.houseBot(tier: tier, arena: choice.arenaID)
    }

    /// The name for each id, so the result sheet can print them even before the arena answers.
    static func names(for choice: QuickFightChoice, tier: CareerTier, seed: Int) -> [String: String] {
        var names = [firstOpponentID: opponent(for: choice, tier: tier, seed: seed).name]
        if choice.rumble {
            names[secondOpponentID] = filler(tier: tier, index: 3, seed: seed &+ 104_729).name
        }
        return names
    }
}

// MARK: - The picker

/// A compact sheet: arena, opponent, rumble, then FIGHT. Pad navigable like every other menu.
struct QuickFightPicker: View {

    @Bindable var host: ArenaHost
    let bot: BotBuild?
    /// The tier the opponent is built at. The career's own tier if there is a career.
    let tier: CareerTier
    var onFight: (QuickFightChoice) -> Void
    var onCancel: () -> Void

    @State private var choice = QuickFightChoice()
    @State private var didLoad = false

    private var focus: PadFocus { PadFocus.shared }
    private var gates: Gates { Gates.snapshot }
    private var catalogue: Catalogue { Catalogue.shared }
    private var rivals: [CareerCatalogue.RivalEntry] { CareerCatalogue.shared.rivals }

    var body: some View {
        ZStack {
            Stage.ground.ignoresSafeArea()
            StageStill(kind: .empty).opacity(0.4).ignoresSafeArea()
            Stage.ink.opacity(0.62).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                header
                HStack(alignment: .top, spacing: 18) {
                    left
                    right
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            if !didLoad {
                didLoad = true
                choice = QuickFightChoice.remembered(gates: gates)
                focus.pushContext()
            }
            registerFocus()
        }
        .onDisappear { focus.popContext() }
        .onChange(of: choice) { _, _ in registerFocus() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Text("QUICK FIGHT")
                .font(Stage.display(26))
                .kerning(1.8)
                .foregroundStyle(Stage.text)
            Spacer(minLength: 8)
            PadHintBar()
        }
    }

    // MARK: The choices

    private var left: some View {
        GlassPanel(padding: 12) {
            ScrollView {
                // Tight on purpose: at the old spacings the RUMBLE row fell off the bottom of a
                // 402 pt sheet and read as missing rather than as something to scroll to.
                VStack(alignment: .leading, spacing: 8) {
                    StageHeading("Arena")
                    arenaGrid

                    StageHeading("Opponent")
                    opponentRow

                    StageHeading("Rumble")
                    rumbleRow

                    StageHeading("House bot")
                    houseBotRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var arenaGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
            ForEach(catalogue.arenas) { arena in
                arenaChip(arena)
            }
        }
    }

    private func arenaChip(_ arena: Catalogue.ArenaEntry) -> some View {
        let open = gates.arenaAvailable(arena.id)
        let chosen = choice.arenaID == arena.id
        let focused = focus.isFocused("arena-\(arena.id)")
        // The arena's own key art (design system section 6), cropped to a band so all six fit
        // on the sheet with the opponent, the rumble and the house bot rows still under them.
        // A locked one says "Full game" in the `line` colour over greyed art: visible and
        // readable, which is what `Gates` asks for, and never hidden.
        return Button {
            guard open else { return }
            choice.arenaID = arena.id
        } label: {
            GeometryReader { proxy in
                ArenaCard(
                    arenaID: arena.id,
                    name: arena.name,
                    width: proxy.size.width,
                    // The card is as tall as its tile, never taller: at 2.35 a wide tile drew
                    // 70 pt into a 48 pt row and its name ran into the OPPONENT heading.
                    aspect: max(2.35, proxy.size.width / 48),
                    selected: chosen && open,
                    focused: focused,
                    locked: !open,
                    inPicker: true,
                    // The hazard used to sit here and was cut to "floor grinders on both..." on a
                    // 402 pt phone; the chosen arena's hazard is now a whole sentence on the card
                    // to the right, and the tile keeps its name (QA 2026-09-25).
                    note: open ? "" : "Full game"
                )
            }
            .frame(height: 48)
            .clipped()
        }
        .buttonStyle(.plain)
        .disabled(!open)
    }

    // The line that used to sit under the grid ("4 arenas unlock with the full game") is gone:
    // every locked card says "Full game" on its own face now, and the RUMBLE row needs the room
    // more than the sentence does (wave P, agent H).

    private var opponentRow: some View {
        valueRow(
            id: "opponent",
            label: "Who",
            value: opponentName,
            blurb: opponentBlurb
        ) { delta in
            cycleOpponent(delta)
        }
    }

    private var rumbleRow: some View {
        valueRow(
            id: "rumble",
            label: "Three machines",
            value: choice.rumble ? "On" : "Off",
            blurb: choice.rumble
                ? "You, your pick, and one more. Last one still moving wins."
                : "One on one."
        ) { _ in
            choice.rumble.toggle()
        }
    }

    /// The house bot (brief v4 section 3). On from Regional up and off at Scrapyard until the
    /// player says otherwise; a rumble has three machines already and never gets one.
    private var houseBotRow: some View {
        let on = choice.houseBotOn(tier: tier)
        let name = QuickFight.houseBot(for: choice, tier: tier)
            .map { CareerEngine.houseBotName($0.id) } ?? ""
        return valueRow(
            id: "houseBot",
            label: "House bot",
            value: choice.rumble ? "Off" : (on ? "On" : "Off"),
            blurb: rumbleOrHouseBotBlurb(on: on, name: name)
        ) { _ in
            guard !choice.rumble else { return }
            choice.houseBot = !on
        }
    }

    private func rumbleOrHouseBotBlurb(on: Bool, name: String) -> String {
        if choice.rumble {
            return "A rumble has three machines already. No house bot."
        }
        if on {
            return "\(name) guards the marked corner and comes out hunting at two minutes."
        }
        return "Nothing in the corner. Just the two of you."
    }

    /// A label, a value between two chevrons, and a line about it. The same row the settings use.
    private func valueRow(
        id: String,
        label: String,
        value: String,
        blurb: String,
        adjust: @escaping (Int) -> Void
    ) -> some View {
        let focused = focus.isFocused(id)
        return Button {
            adjust(1)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(label.uppercased())
                        .font(Stage.display(14))
                        .kerning(0.8)
                        .foregroundStyle(Stage.text)
                    Spacer(minLength: 8)
                    chevron("chevron.left") { adjust(-1) }
                    Text(value)
                        .font(Stage.figure(value, size: 13))
                        .foregroundStyle(Stage.textDim)
                        .frame(minWidth: 110, alignment: .trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(BroadcastType.floorScale(.numerals, size: 13, wanted: 0.7))
                    chevron("chevron.right") { adjust(1) }
                }
                Text(blurb)
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.textFaint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background {
                CutRect(9)
                    .fill(focused ? Stage.selectedFill : Stage.type.opacity(0.05))
            }
        }
        .buttonStyle(.plain)
    }

    private func chevron(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(Stage.textDim)
                .frame(width: 24, height: 20)
                .background {
                    CutRect(6)
                        .fill(Stage.type.opacity(0.06))
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: The summary and the buttons

    private var right: some View {
        VStack(alignment: .leading, spacing: 9) {
            GlassPanel(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    StageHeading("The card")
                    StageStat(label: "Your machine", value: bot?.name ?? "none")
                    StageStat(label: "Arena", value: catalogue.arena(choice.arenaID)?.name ?? choice.arenaID)
                    StageStat(label: "Opponent", value: opponentName)
                    // The BOTS row (2 or 3) went (integration 2026-09-28): the RUMBLE row on the
                    // left already says it, and in the Blueprint type the column was taller than a
                    // 402 pt phone, which pushed the QUICK FIGHT title off the top.
                    if let hazard = catalogue.arena(choice.arenaID)?.hazard, !hazard.isEmpty {
                        Text("Hazard: \(hazard.capitalizedFirst).")
                            .font(Stage.body(13))
                            .foregroundStyle(Stage.typeDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(tierLine)
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            StageButton("Fight", kind: .primary, enabled: bot?.isValid ?? false, focusID: "go") {
                start()
            }
            StageButton("Cancel", kind: .quiet, focusID: "cancel") { onCancel() }

            Spacer(minLength: 0)
        }
        .frame(width: 232)
    }

    private var opponentName: String {
        if choice.isFiller { return "Anyone" }
        return CareerCatalogue.shared.rival(choice.rivalID)?.name ?? "Anyone"
    }

    private var opponentBlurb: String {
        if choice.isFiller { return "A machine made up for the night, at your own level." }
        guard let rival = CareerCatalogue.shared.rival(choice.rivalID) else { return "" }
        return "\(rival.roboteer). \(rival.personality.capitalizedFirst)."
    }

    /// Quick Fight builds its opponent at the strength of one of the five Series, and the Series
    /// is the career's own (wave P). The words tier, circuit and season never reach the player.
    private var tierLine: String {
        "Built at Series \(tier.index + 1) strength, the \(tier.title)."
    }

    // MARK: Actions

    private func cycleOpponent(_ delta: Int) {
        // The list is the made up entrant first, then every rival in catalogue order.
        var ids = [""]
        ids.append(contentsOf: rivals.map(\.id))
        let current = ids.firstIndex(of: choice.rivalID) ?? 0
        let next = (current + delta + ids.count) % ids.count
        choice.rivalID = ids[next]
    }

    private func start() {
        guard bot?.isValid ?? false else { return }
        choice.remember()
        onFight(choice)
    }

    // MARK: Pad

    private func registerFocus() {
        var items: [PadItem] = catalogue.arenas.map { arena in
            PadItem("arena-\(arena.id)", enabled: gates.arenaAvailable(arena.id)) {
                choice.arenaID = arena.id
            }
        }
        items.append(PadItem("opponent") { cycleOpponent(1) })
        items.append(PadItem("rumble") { choice.rumble.toggle() })
        items.append(PadItem("houseBot", enabled: !choice.rumble) {
            choice.houseBot = !choice.houseBotOn(tier: tier)
        })
        items.append(PadItem("go", enabled: bot?.isValid ?? false) { start() })
        items.append(PadItem("cancel") { onCancel() })

        focus.set(
            items,
            back: { onCancel() },
            sideways: { event in
                let delta = event == .left ? -1 : 1
                switch focus.currentID {
                case "opponent":
                    cycleOpponent(delta)
                    return true
                case "rumble":
                    choice.rumble.toggle()
                    return true
                case "houseBot":
                    if !choice.rumble { choice.houseBot = !choice.houseBotOn(tier: tier) }
                    return true
                default:
                    // The arena chips are a grid, so left and right walk them as a list.
                    return false
                }
            }
        )
    }
}
