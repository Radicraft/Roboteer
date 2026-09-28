//
//  UnlockView.swift
//  The one unlock screen. It is shown in exactly two places and nowhere else:
//
//    1. Once, after the Regional final is won (`Gates.shouldOfferAfterRegionalFinal`).
//    2. Whenever the player opens the row in Settings.
//
//  Never during a fight, never on a timer, never at a discount, never a second time by itself.
//  Brief section 14. If a fourth place to show this ever appears in a diff, that diff is wrong.
//
//  It states the whole deal in plain sentences: what the free game gave, what the full game adds,
//  the price in the player's own currency, and that this is the only purchase in the game.
//

import SwiftUI

struct UnlockView: View {

    var host: ArenaHost = ArenaHost.shared
    /// Called when the player closes the screen, bought or not.
    var onClose: () -> Void

    private var store: StoreService { StoreService.shared }

    private var focus: PadFocus { PadFocus.shared }

    private enum Item: String {
        case unlock
        case restore
        case close
    }

    // MARK: - The copy

    /// What the free half already gave them. Said in the past tense on purpose: this is what they
    /// have played, not a feature list.
    private let free: [String] = [
        "Series 1 and 2, the Scrapyard and the Regional",
        "The Yard and The Grinder",
        "THRESHER and CINDER, the house bots of the first two Series",
        "The workshop test arena, with the camera off the leash",
        "Two bots in the garage"
    ]

    /// What the purchase opens.
    private let full: [String] = [
        "Series 3, 4 and 5: the National, the Championship and the Masters",
        "Four more arenas: the Drop Zone, the Furnace, the Crush and the Coliseum",
        "Three more house bots: BANDSAW, GRUDGE and ANVIL",
        "The full part library in the builder",
        "Garage capacity up to five machines",
        "Side events: Sumo, Gauntlet, Pinball, Football and Wall Smash",
        "Replays, the free camera and shareable clips",
        "The async ladder against other players' machines"
    ]

    var body: some View {
        ZStack {
            StageBackdrop(host: host, still: .empty, dim: 0.62)
            // A purchase screen is not a place to be dragging the stage about behind the panels.
            StageTouchBlocker()

            VStack(alignment: .leading, spacing: 12) {
                header

                HStack(alignment: .top, spacing: 16) {
                    freePanel
                    fullPanel
                    buyPanel
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            store.clearMessages()
            Task { await store.loadProduct() }
            registerFocus()
        }
        .onDisappear { focus.clear() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(store.isUnlocked ? "THE FULL GAME" : "UNLOCK THE FULL GAME")
                .font(Stage.display(26))
                .kerning(1.8)
                .foregroundStyle(Stage.text)

            Text("One purchase. No subscription, no ads, no other purchases.")
                .font(Stage.body(13))
                .foregroundStyle(Stage.textDim)
                .lineLimit(1)
                .minimumScaleFactor(BroadcastType.floorScale(.body, size: 13, wanted: 0.7))

            Spacer(minLength: 8)

            PadHintBar(showsBack: true)
        }
    }

    // MARK: - The two lists

    private var freePanel: some View {
        GlassPanel(padding: 12) {
            VStack(alignment: .leading, spacing: 7) {
                StageHeading("What you have played")
                ForEach(free, id: \.self) { line in
                    bullet(line, symbol: "checkmark", tint: Stage.textDim)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // Narrower than it was (232): the free list is five short lines, and the middle column
        // needs the room so its eight lines are all on screen on a 402 pt phone (QA 2026-09-25).
        .frame(width: 196)
    }

    private var fullPanel: some View {
        GlassPanel(padding: 12) {
            VStack(alignment: .leading, spacing: 7) {
                StageHeading("What the full game adds")
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(full, id: \.self) { line in
                            bullet(line, symbol: "plus", tint: Stage.text)
                        }
                    }
                    .padding(.bottom, 2)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
    }

    private func bullet(_ line: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(tint == Stage.text ? Stage.gold : Stage.textFaint)
                .frame(width: 11)
            Text(line)
                .font(Stage.body(13))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }

    // MARK: - The price and the buttons

    private var buyPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            GlassPanel(padding: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    if store.isUnlocked {
                        Text("UNLOCKED")
                            .font(Stage.display(24))
                            .kerning(1.4)
                            .foregroundStyle(Stage.gold)
                        Text("Thank you. Everything is open, on every device signed in to this Apple Account.")
                            .font(Stage.body(13))
                            .foregroundStyle(Stage.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        StageHeading("One purchase")
                        // A price is a figure, "Price unavailable" is words (integration 2026-09-28).
                        Text(priceLine)
                            .font(Stage.figure(priceLine, size: 30))
                            .foregroundStyle(Stage.text)
                            .lineLimit(1)
                            .minimumScaleFactor(BroadcastType.floorScale(.numerals, size: 30, wanted: 0.6))
                        Text("Everything you have built and won carries across. Nothing resets.")
                            .font(Stage.body(13))
                            .foregroundStyle(Stage.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let message = statusLine {
                        Text(message)
                            .font(Stage.body(13))
                            .foregroundStyle(store.state.failure == nil ? Stage.textDim : Stage.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !store.isUnlocked {
                StageButton(
                    "Unlock everything",
                    kind: .primary,
                    enabled: !store.state.isBusy,
                    focusID: Item.unlock.rawValue
                ) {
                    Task { await store.purchase() }
                }

                StageButton(
                    "Restore purchases",
                    kind: .glass,
                    enabled: !store.state.isBusy,
                    focusID: Item.restore.rawValue
                ) {
                    Task { await store.restore() }
                }
            }

            StageButton(
                store.isUnlocked ? "Back to the game" : "Not now",
                kind: .quiet,
                focusID: Item.close.rawValue
            ) {
                onClose()
            }

            Spacer(minLength: 0)
        }
        .frame(width: 232)
    }

    /// The localized price, or an honest sentence while the store has not answered.
    private var priceLine: String {
        if let price = store.priceText { return price }
        return store.didLoad ? "Price unavailable" : "Loading the price"
    }

    private var statusLine: String? {
        if let failure = store.state.failure { return failure }
        if let notice = store.notice { return notice }
        switch store.state {
        case .purchasing: return "Waiting on the App Store."
        case .loading: return "Checking with the App Store."
        default: return nil
        }
    }

    // MARK: - Pad

    private func registerFocus() {
        var items: [PadItem] = []
        if !store.isUnlocked {
            items.append(PadItem(Item.unlock.rawValue) { Task { await store.purchase() } })
            items.append(PadItem(Item.restore.rawValue) { Task { await store.restore() } })
        }
        items.append(PadItem(Item.close.rawValue) { onClose() })
        focus.set(items, back: { onClose() })
    }
}

// MARK: - Presenting it

extension View {

    /// The only way to put the unlock screen on screen. Two callers: the Settings row, and the
    /// career once the Regional final is won.
    func unlockScreen(isPresented: Binding<Bool>, host: ArenaHost = ArenaHost.shared, onDismiss: @escaping () -> Void = {}) -> some View {
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
            UnlockView(host: host) { isPresented.wrappedValue = false }
        }
    }
}
