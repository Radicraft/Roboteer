//
//  ContentView.swift
//  The Stage 1 spike screen. One embedded Godot view, one button, one readout.
//

import SwiftUI
import SwiftGodot
import SwiftGodotKit

struct ContentView: View {
    @Bindable var model: SpikeModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Roboteer bridge spike")
                    .font(.title2.weight(.semibold))

                arenaView

                controls

                if let errorText = model.errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                readout

                resultPanel
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Arena

    private var arenaView: some View {
        GodotAppView(
            onReady: { handle in model.onReady(handle) },
            onMessage: { dictionary in model.receive(dictionary) }
        )
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .environment(\.godotApp, model.app)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Button("Send fight") {
                model.sendFightConfig()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.arenaReady)

            Button("Sample memory") {
                model.sampleMemoryNow()
            }
            .buttonStyle(.bordered)

            Spacer()

            Text(model.arenaReady ? "Arena ready" : "Waiting for the arena")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Readout

    private var readout: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Measurements")
                .font(.subheadline.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                row("Ready", milliseconds(model.readyMs))
                row("Arena ready", milliseconds(model.arenaReadyMs))
                row("Round trip", milliseconds(model.roundTripMs))
                row("Memory at ready", megabytes(model.memoryAtReadyMB))
                row("Memory plus 5 s", megabytes(model.memoryPlusFiveMB))
                row("Memory latest", megabytes(model.memoryLatestMB))
                row("Godot version", model.godotVersion)
                row("Last message", model.lastMessageType)
            }
            .font(.system(.footnote, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
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
            Text("Fight result")
                .font(.subheadline.weight(.semibold))

            ScrollView(.vertical) {
                Text(model.resultJSON.isEmpty ? "Nothing received yet." : model.resultJSON)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 260)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
