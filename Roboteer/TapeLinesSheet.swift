//
//  TapeLinesSheet.swift
//  The player's own two lines for the tale of the tape (wave D walk-outs,
//  docs/wave-d-walkout-notes.md).
//
//  Reached from the builder's header ("Tale of the tape"). Two free-text lines, a STRENGTH and a
//  WEAKNESS, each cut to 60 characters and trimmed to one line; nothing is policed. Left empty,
//  the card writes its own from the build, and the placeholder shows the player which line that
//  would be. Saved on the machine (`BotBuild.strengthLine` / `.weaknessLine`) the moment the sheet
//  closes.
//
//  INTEGRATION (wave-c-menus rebuilds the builder): this file is self-contained. The builder only
//  needs a way in: `@State private var showsTape = false`, a link that sets it, and
//  `.sheet(isPresented: $showsTape) { TapeLinesSheet(build: build) }`. On main that link sits in
//  `BuilderBody.header` beside the name field.
//

import SwiftUI
import SwiftData

struct TapeLinesSheet: View {

    @Bindable var build: BotBuild

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var strength = ""
    @State private var weakness = ""
    @FocusState private var focus: Field?

    private enum Field { case strength, weakness }

    private var made: (strength: String, weakness: String) { TaleOfTheTape.defaultLines(for: build.spec) }

    var body: some View {
        ZStack(alignment: .top) {
            Stage.ink.ignoresSafeArea()
            // Top aligned and compact: in landscape the keyboard takes the lower half.
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TALE OF THE TAPE")
                            .font(Stage.display(22))
                            .foregroundStyle(Stage.text)
                        Text("Read out as \(build.name) walks out. Leave a line empty and the card writes its own.")
                            .font(Stage.body(13))
                            .foregroundStyle(Stage.textDim)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    StageButton("Done", kind: .primary) { close() }
                        .frame(width: 120)
                }
                line(title: "Strength", text: $strength, placeholder: made.strength, field: .strength)
                line(title: "Weakness", text: $weakness, placeholder: made.weakness, field: .weakness)
            }
            .padding(.horizontal, 26)
            .padding(.top, 14)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .onAppear {
            strength = build.strengthLine ?? ""
            weakness = build.weaknessLine ?? ""
        }
        .onDisappear { save() }
    }

    private func line(title: String, text: Binding<String>, placeholder: String, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title.uppercased())
                    .font(Stage.label(11, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(field == .weakness ? Stage.danger : Stage.textDim)
                Spacer()
                Text("\(text.wrappedValue.count)/\(TaleOfTheTape.lineLimit)")
                    .font(Stage.label(11))
                    .foregroundStyle(Stage.textFaint)
                    .monospacedDigit()
            }
            TextField(placeholder, text: text)
                .font(Stage.body(16))
                .foregroundStyle(Stage.text)
                .textInputAutocapitalization(.sentences)
                .submitLabel(field == .strength ? .next : .done)
                .focused($focus, equals: field)
                .onSubmit {
                    if field == .strength { focus = .weakness } else { close() }
                }
                .onChange(of: text.wrappedValue) { _, new in
                    // The limit as they type: a pasted paragraph stops at the limit.
                    if new.count > TaleOfTheTape.lineLimit {
                        text.wrappedValue = String(new.prefix(TaleOfTheTape.lineLimit))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background { CutRect(8).fill(Stage.type.opacity(0.07)) }
                .accessibilityLabel(title)
        }
    }

    private func save() {
        let s = TaleOfTheTape.clean(strength)
        let w = TaleOfTheTape.clean(weakness)
        build.strengthLine = s.isEmpty ? nil : s
        build.weaknessLine = w.isEmpty ? nil : w
        try? context.save()
    }

    private func close() {
        save()
        dismiss()
    }
}
