//
//  RetryPromptView.swift
//  STUB (coordinator). Agent B1 builds the loss/draw retry prompt here. Signature is the contract.
//

import SwiftUI

struct RetryPromptView: View {
    @Bindable var host: ArenaHost
    let report: MatchReport
    let repairBill: RepairBill
    let scrap: Int
    var onRetry: () -> Void
    var onRepairAndRetry: () -> Void
    var onGarage: () -> Void

    var body: some View {
        Text("Retry").onTapGesture { onRetry() }
    }
}
