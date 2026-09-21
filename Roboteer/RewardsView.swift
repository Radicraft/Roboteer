//
//  RewardsView.swift
//  STUB (coordinator). Agent B1 builds brief v5 section 6 here. Signature is the contract.
//

import SwiftUI

struct RewardsView: View {
    @Bindable var host: ArenaHost
    let rewards: Rewards
    var onContinue: () -> Void

    var body: some View {
        Text("Rewards").onTapGesture { onContinue() }
    }
}
