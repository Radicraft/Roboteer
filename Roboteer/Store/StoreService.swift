//
//  StoreService.swift
//  The one purchase. StoreKit 2, one non-consumable, no subscription, no consumables, nothing
//  inside the game for sale (brief section 9's hard rule and section 14).
//
//  Everything the rest of the app needs is `isUnlocked`. The gates in `Gates.swift` read it and
//  nothing else reads StoreKit directly.
//
//  The entitlement is settled from three places, in this order:
//    1. `Transaction.currentEntitlements` at launch, which is the local receipt and works offline.
//    2. `Transaction.updates`, which catches a purchase made on another device, a Family Sharing
//       grant arriving, a refund, or an Ask to Buy approval landing days later.
//    3. `AppStore.sync()` from the Restore purchases row, which is the only thing that ever asks
//       the player for their Apple Account password.
//

import Foundation
import StoreKit
import OSLog

@MainActor
@Observable
final class StoreService {

    /// One service for the life of the process. The gates read this.
    static let shared = StoreService()

    /// The only product this app will ever have.
    static let productID = "com.radicraft.roboteer.unlock"

    /// What the unlock screen is doing right now.
    enum State: Equatable {
        case idle
        /// Asking the App Store for the product, or running a restore.
        case loading
        /// The payment sheet is up.
        case purchasing
        /// Something went wrong, in a sentence the player can read.
        case failed(String)

        var isBusy: Bool { self == .loading || self == .purchasing }

        var failure: String? {
            if case .failed(let message) = self { return message }
            return nil
        }
    }

    /// The whole game, or the free two circuits. Every gate hangs off this one bool.
    private(set) var isUnlocked = false

    /// A copy of `isUnlocked` that code off the main actor can read, kept in step by
    /// `setUnlocked`. `Gates.snapshot` is the only thing that should use it: a view already on the
    /// main actor reads `Gates.current` instead.
    nonisolated(unsafe) private(set) static var unlockedSnapshot = false

    private func setUnlocked(_ value: Bool) {
        isUnlocked = value
        StoreService.unlockedSnapshot = value
    }

    /// The product, for its localized display price. Nil until the store answers, and nil forever
    /// if the device is offline, which is why no screen may depend on it to draw.
    private(set) var product: Product?

    private(set) var state: State = .idle

    /// A plain sentence about something that is not an error: a purchase waiting on approval, or a
    /// restore that found nothing. Cleared by the next action.
    private(set) var notice: String?

    /// True once the launch pass has finished, so the unlock screen knows the price is simply not
    /// coming rather than still on its way.
    private(set) var didLoad = false

    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var started = false

    private let log = Logger(subsystem: "com.radicraft.roboteer", category: "store")

    private init() {
        // A QA override settles the entitlement before anything asks, so a simulator run can see
        // both halves of the game without a payment sheet.
        switch StoreService.override {
        case .unlocked: setUnlocked(true)
        case .locked: setUnlocked(false)
        case .none: break
        }
        // The entitlement has to be known before the first gate is asked, so the service starts
        // itself the first time anything touches it. `start()` stays public and idempotent so the
        // app root can also call it explicitly at launch.
        start()
    }

    // MARK: - QA override

    enum Override {
        case none
        case unlocked
        case locked
    }

    /// `-unlocked` or `-locked` on the scheme. `-locked` wins if somebody passes both, because the
    /// locked half is the one that needs testing. Never consulted on a device build.
    static var override: Override {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-locked") { return .locked }
        if arguments.contains("-unlocked") { return .unlocked }
        #endif
        return .none
    }

    var isOverridden: Bool { StoreService.override != .none }

    // MARK: - Launch

    /// Called once, from the app's root. Safe to call again; it only ever runs the once.
    func start() {
        guard !started else { return }
        started = true

        updates = Task { [weak self] in
            // This sequence never ends. It is the only listener in the app.
            for await result in Transaction.updates {
                await self?.absorb(result)
            }
        }

        Task { await refresh() }
    }

    /// The local entitlement pass: the receipt on this device, which works with no network.
    func refresh() async {
        if isOverridden {
            didLoad = true
            await loadProduct()
            return
        }

        var owned = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == StoreService.productID else { continue }
            if transaction.revocationDate == nil { owned = true }
        }
        setUnlocked(owned)
        log.info("entitlement at launch: \(owned ? "unlocked" : "locked", privacy: .public)")

        await loadProduct()
        didLoad = true
    }

    /// The price, in the player's own currency and format. Never hardcoded in a view.
    func loadProduct() async {
        if state == .idle { state = .loading }
        do {
            let products = try await Product.products(for: [StoreService.productID])
            product = products.first { $0.id == StoreService.productID }
            if product == nil {
                log.error("the store returned no product for \(StoreService.productID, privacy: .public)")
            }
            state = .idle
        } catch {
            log.error("the store would not load: \(String(describing: error), privacy: .public)")
            state = .idle
        }
    }

    /// The localized price, or nil while the store has not answered.
    var priceText: String? { product?.displayPrice }

    // MARK: - Buying

    func purchase() async {
        notice = nil

        if isOverridden {
            // A QA run has no payment sheet. Say so rather than pretending to buy.
            state = .failed("This run was launched with a store override, so there is nothing to buy.")
            return
        }

        guard let product else {
            state = .failed("The App Store has not sent the price back yet. Check the connection and try again.")
            return
        }

        state = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    setUnlocked(true)
                    await transaction.finish()
                    state = .idle
                    log.info("purchase verified")
                case .unverified(_, let error):
                    state = .failed("That purchase could not be verified. Try Restore purchases in Settings.")
                    log.error("unverified purchase: \(String(describing: error), privacy: .public)")
                }
            case .pending:
                // Ask to Buy, or a payment method that needs approval. The listener picks it up
                // whenever it lands, even in a later session.
                state = .idle
                notice = "That purchase is waiting for approval. The game unlocks by itself as soon as it goes through."
            case .userCancelled:
                state = .idle
            @unknown default:
                state = .idle
            }
        } catch {
            state = .failed("The purchase did not finish. \(error.localizedDescription)")
            log.error("purchase failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Restoring

    /// The Restore purchases row. `AppStore.sync()` is the only call that may ask for a password,
    /// so it is never made on its own; a player has to press the row.
    func restore() async {
        notice = nil

        if isOverridden {
            state = .failed("This run was launched with a store override, so there is nothing to restore.")
            return
        }

        state = .loading
        do {
            try await AppStore.sync()
            await refresh()
            state = .idle
            notice = isUnlocked
                ? "Your purchase is back. Everything is unlocked."
                : "No purchase was found on this Apple Account."
        } catch {
            state = .failed("Restore did not finish. \(error.localizedDescription)")
            log.error("restore failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Clears a failure or a notice so a screen can open clean.
    func clearMessages() {
        notice = nil
        if state.failure != nil { state = .idle }
    }

    // MARK: - Updates

    private func absorb(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        guard transaction.productID == StoreService.productID else { return }

        if transaction.revocationDate == nil {
            if !isOverridden { setUnlocked(true) }
            log.info("entitlement arrived from the update listener")
        } else {
            // A refund or a revoked Family Sharing grant. Progress is untouched; only the door
            // closes again.
            if !isOverridden { setUnlocked(false) }
            log.info("entitlement was revoked")
        }
        await transaction.finish()
    }
}
