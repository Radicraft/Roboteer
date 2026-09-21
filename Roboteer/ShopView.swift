//
//  ShopView.swift
//  STUB (coordinator). Agent B2 builds the Level-gated shop here. Signature is the contract.
//

import SwiftUI
import SwiftData

struct ShopView: View {
    @Bindable var host: ArenaHost
    @Bindable var state: CareerState
    var onClose: () -> Void

    var body: some View {
        Text("Shop").onTapGesture { onClose() }
    }
}
