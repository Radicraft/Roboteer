//
//  ContentView.swift
//  The Stage 1 spike screen, kept for the measurements. One embedded Godot view, one button,
//  one readout. Reached from the root menu as "Bridge spike".
//

import SwiftUI
import SwiftGodot
import SwiftGodotKit

struct ContentView: View {
    @Bindable var host: ArenaHost

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("BRIDGE SPIKE")
                    .font(Stage.display(28))
                    .kerning(Stage.Tracking.display(28))
                    .foregroundStyle(Stage.type)

                arenaView

                controls

                if let errorText = host.errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(Stage.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                readout

                resultPanel
            }
            .padding(16)
        }
        .background(Stage.ink)
        .navigationTitle("Bridge spike")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { host.arenaScreenAppeared() }
        .onDisappear { host.arenaScreenLeft() }
    }

    // MARK: - Arena

    private var arenaView: some View {
        GodotAppView(
            onReady: { handle in host.onReady(handle) },
            onMessage: { dictionary in host.receive(dictionary) }
        )
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Stage.ink)
        .clipShape(PlateRect())
        .environment(\.godotApp, host.app)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Button("Send fight") {
                host.sendSpikeConfig()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!host.arenaReady)

            Button("Sample memory") {
                host.sampleMemoryNow()
            }
            .buttonStyle(.bordered)

            Spacer()

            Text(host.arenaReady ? "Arena ready" : "Waiting for the arena")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Readout

    private var readout: some View {
        VStack(alignment: .leading, spacing: 6) {
            StageHeading("Measurements")

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                row("Ready", milliseconds(host.readyMs))
                row("Arena ready", milliseconds(host.arenaReadyMs))
                row("Round trip", milliseconds(host.roundTripMs))
                row("Memory at ready", megabytes(host.memoryAtReadyMB))
                row("Memory plus 5 s", megabytes(host.memoryPlusFiveMB))
                row("Memory latest", megabytes(host.memoryLatestMB))
                row("Godot version", host.godotVersion)
                row("Last message", host.lastMessageType)
            }
            .font(.system(.footnote, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Stage.glass)
        .clipShape(PlateRect())
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(Stage.typeDim)
            Text(value).foregroundStyle(Stage.type)
        }
    }

    private func milliseconds(_ value: Double?) -> String {
        guard let value else { return "not yet" }
        return String(format: "%.0f ms", value)
    }

    private func megabytes(_ value: Double?) -> String {
        guard let value else { return "not yet" }
        return String(format: "%.1f MB", value)
    }

    // MARK: - Result

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            StageHeading("Fight result")

            ScrollView(.vertical) {
                Text(host.resultJSON.isEmpty ? "Nothing received yet." : host.resultJSON)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 260)
            .background(Stage.glass)
            .clipShape(PlateRect())
        }
    }
}
