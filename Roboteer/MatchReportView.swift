//
//  MatchReportView.swift
//  STUB (coordinator). Agent B1 builds brief v5 section 5 here. Signature is the contract.
//

import SwiftUI

struct MatchReportView: View {
    @Bindable var host: ArenaHost
    let report: MatchReport
    var onContinue: () -> Void

    var body: some View {
        Text("Match report").onTapGesture { onContinue() }
    }
}
