//
//  Gates.swift
//  What the free game contains, and what the one purchase opens. Brief section 14.
//
//  This type is pure: give it a bool and it answers every question the wall poses, with no store,
//  no UserDefaults and no SwiftData in the answer. That is deliberate. The wall has to be provable
//  by reading one file, and the free half has to be checkable without buying anything.
//
//  The free half, in one place:
//    tiers      Scrapyard, Regional
//    arenas     The Yard, The Grinder, and the workshop test arena, which is never gated
//    boss       CINDER
//    parts      the catalogue's `career.starting_unlocks` plus the Scrapyard and Regional drips
//    garage     two bots
//    modes      career, quick fight, the test arena
//  Everything else needs the unlock: National, Championship and Masters, the other four arenas,
//  the other four bosses, the rest of the part library, garage slots three to five, side events,
//  replays and sharing, and the async ladder.
//
//  Nothing in here is ever sold separately and nothing in here is ever discounted. One door, one
//  charge, one price.
//

import Foundation

struct Gates {

    /// The whole game, or the free two circuits.
    let isUnlocked: Bool

    init(isUnlocked: Bool) {
        self.isUnlocked = isUnlocked
    }

    /// The gates as they stand right now. Every screen uses this.
    @MainActor
    static var current: Gates { Gates(isUnlocked: StoreService.shared.isUnlocked) }

    /// The gates as read from anywhere, including code that is not on the main actor (the
    /// builder's lock notes are asked for inside a view body that is not isolated). It reads the
    /// snapshot `StoreService` keeps in step with the entitlement.
    static var snapshot: Gates { Gates(isUnlocked: StoreService.unlockedSnapshot) }

    /// The gates with everything open, for previews and for the parts of the career self test that
    /// are not about the wall.
    static let open = Gates(isUnlocked: true)

    // MARK: - The free lists

    /// The two free circuits. The catalogue's own `free` flag decides; this is the fallback for an
    /// empty or damaged catalogue.
    static let freeTierIDs: Set<String> = ["scrapyard", "regional"]

    /// The Yard and The Grinder, which are the two tiers' arenas.
    static let freeArenaIDs: Set<String> = ["yard", "grinder"]

    /// One boss encounter in the free half, and it is the best one to meet first.
    static let freeBossIDs: Set<String> = ["cinder"]

    /// The workshop test arena, which is the game's tutorial and is never behind the wall.
    static let testArenaID = "test"

    /// The free part library, read from `Shared/parts.json`: `career.starting_unlocks` plus the
    /// Scrapyard and Regional blueprint drips. If the career block is missing this falls back to
    /// the list below, which is docs/stage5-spec.md section 6 written out by hand.
    static var freePartIDs: Set<String> {
        let catalogue = CareerCatalogue.shared
        guard !catalogue.startingUnlocks.isEmpty, catalogue.tier(.regional) != nil else {
            // TODO: remove once `career` is guaranteed present in every shipped parts.json.
            return fallbackFreePartIDs
        }
        return catalogue.unlocks(upTo: .regional)
    }

    /// Starting unlocks plus the Scrapyard and Regional drips, matching stage5-spec section 6.
    /// Only used when the catalogue did not load.
    static let fallbackFreePartIDs: Set<String> = [
        // starting_unlocks
        "wedge", "box", "2wd", "4wd", "flipper", "ram", "saw",
        "steel", "hdpe", "polycarbonate", "titanium", "srimech", "spare_battery",
        // Scrapyard drip
        "axe", "pyramid", "vertical_spinner",
        // Regional drip
        "crusher", "long_low", "6wd", "horizontal_spinner", "tracks"
    ]

    /// Garage capacity in the free half, whatever the tier would otherwise allow.
    static let freeGarageCapacity = 2

    // MARK: - The questions

    func tierAvailable(_ tier: CareerTier) -> Bool {
        if isUnlocked { return true }
        if let entry = CareerCatalogue.shared.tier(tier) { return entry.free }
        return Gates.freeTierIDs.contains(tier.rawValue)
    }

    func tierAvailable(_ tierID: String) -> Bool {
        tierAvailable(CareerTier.named(tierID))
    }

    /// The last tier this player may enter. Regional while the game is locked.
    var highestTier: CareerTier {
        CareerTier.allCases.last { tierAvailable($0) } ?? .scrapyard
    }

    /// The first tier behind the wall, which is what the unlock screen names.
    var firstLockedTier: CareerTier? {
        CareerTier.allCases.first { !tierAvailable($0) }
    }

    func arenaAvailable(_ id: String) -> Bool {
        if isUnlocked { return true }
        if id == Gates.testArenaID { return true }
        return Gates.freeArenaIDs.contains(id)
    }

    func bossAvailable(_ id: String) -> Bool {
        isUnlocked || Gates.freeBossIDs.contains(id)
    }

    /// Whether the builder may fit this part at all. The career's own blueprint gate is separate
    /// and stricter early on: a part has to be earned as well as unlocked.
    func partAvailable(_ id: String) -> Bool {
        isUnlocked || Gates.freePartIDs.contains(id)
    }

    /// The tier's capacity, held at two while the game is locked.
    func garageCapacity(forTier tier: CareerTier) -> Int {
        let earned = CareerCatalogue.shared.tier(tier)?.garageCapacity ?? 1
        return isUnlocked ? earned : min(Gates.freeGarageCapacity, earned)
    }

    /// A convenience for the garage: is this slot number (1 based) open.
    func garageSlotAvailable(_ slot: Int, tier: CareerTier) -> Bool {
        slot <= garageCapacity(forTier: tier)
    }

    var sideEventsAvailable: Bool { isUnlocked }
    var replaysAvailable: Bool { isUnlocked }
    /// Sharing a clip is part of replays and goes with them.
    var sharingAvailable: Bool { isUnlocked }
    var ladderAvailable: Bool { isUnlocked }

    /// Never gated, ever: the career itself, quick fight with what you own, and the test arena.
    var careerAvailable: Bool { true }
    var quickFightAvailable: Bool { true }
    var testArenaAvailable: Bool { true }

    // MARK: - What the player is told

    /// Everything that can be locked, so one function writes every sentence.
    enum Locked: Equatable {
        case tier(CareerTier)
        case arena(String)
        case boss(String)
        case part(String)
        case garageSlot(Int)
        case sideEvents
        case replays
        case sharing
        case ladder
    }

    /// The sentence that goes on a locked row. Plain, short, the same promise every time, and it
    /// never nags: it says what opens the thing, not what to press.
    func lockedReason(_ locked: Locked) -> String {
        switch locked {
        case .tier(let tier):
            let name = CareerCatalogue.shared.tier(tier)?.name ?? tier.rawValue.capitalizedFirst
            return "The \(name) circuit unlocks with the full game."
        case .arena(let id):
            let name = Catalogue.shared.arena(id)?.name ?? id.capitalizedFirst
            return "\(name) unlocks with the full game."
        case .boss(let id):
            let name = CareerCatalogue.shared.boss(id)?.name ?? id.uppercased()
            return "\(name) unlocks with the full game."
        case .part:
            return "Unlocks with the full game."
        case .garageSlot(let slot):
            return "Garage slot \(slot) unlocks with the full game."
        case .sideEvents:
            return "Side events unlock with the full game."
        case .replays:
            return "Replays unlock with the full game."
        case .sharing:
            return "Sharing a clip unlocks with the full game."
        case .ladder:
            return "The ladder unlocks with the full game."
        }
    }

    /// The reason, or nil when the thing is open. Views take this shape: a nil means draw it plain.
    func lockedReasonIfLocked(_ locked: Locked) -> String? {
        guard !available(locked) else { return nil }
        return lockedReason(locked)
    }

    /// Is this particular thing open.
    func available(_ locked: Locked) -> Bool {
        switch locked {
        case .tier(let tier): return tierAvailable(tier)
        case .arena(let id): return arenaAvailable(id)
        case .boss(let id): return bossAvailable(id)
        case .part(let id): return partAvailable(id)
        case .garageSlot(let slot): return isUnlocked || slot <= Gates.freeGarageCapacity
        case .sideEvents: return sideEventsAvailable
        case .replays: return replaysAvailable
        case .sharing: return sharingAvailable
        case .ladder: return ladderAvailable
        }
    }

    // MARK: - Where the wall is offered

    /// The one moment the game ever brings the wall up by itself: the Regional final has just been
    /// won, which is the warmest a player is ever going to be. Once, and never again.
    ///
    /// The career screens call this after settling the Regional final, and call
    /// `markRegionalOfferShown()` whether the player bought or pressed Not now. Nothing else in the
    /// app may present the unlock screen except the Settings row.
    @MainActor
    static var shouldOfferAfterRegionalFinal: Bool {
        guard !StoreService.shared.isUnlocked else { return false }
        return !regionalOfferShown
    }

    /// The one shot flag. Set it the moment the screen appears, not when it closes, so a crash on
    /// the unlock screen cannot turn one offer into two.
    static func markRegionalOfferShown() {
        UserDefaults.standard.set(true, forKey: Key.regionalOfferShown)
    }

    static var regionalOfferShown: Bool {
        UserDefaults.standard.bool(forKey: Key.regionalOfferShown)
    }

    /// QA only: lets a tester see the offer again without wiping the app.
    static func resetRegionalOffer() {
        UserDefaults.standard.removeObject(forKey: Key.regionalOfferShown)
    }

    private enum Key {
        static let regionalOfferShown = "store.regionalOfferShown"
    }
}
