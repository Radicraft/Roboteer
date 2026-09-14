//
//  DesignSystem.swift
//  The AAA cinematic menu look (docs/stage2-art-direction.md, owner decision 2026-09-13):
//  a dark stage with the player's own bot under moving lights, translucent dark glass panels over
//  it, bold condensed white capitals, and gold for scrap and winner marks only.
//
//  No Game Boy greens anywhere in the menus. The arena HUD is Godot's and is untouched.
//

import SwiftUI

// MARK: - Tokens

enum Stage {

    /// The one accent. Scrap and winner marks, nothing else.
    static let gold = Color(hex: 0xF2C14E)

    static let text = Color.white
    static let textDim = Color.white.opacity(0.68)
    static let textFaint = Color.white.opacity(0.42)

    static let edge = Color.white.opacity(0.18)
    static let edgeBright = Color.white.opacity(0.45)

    static let panel = Color.black.opacity(0.42)
    static let panelDeep = Color.black.opacity(0.62)
    static let ground = Color(hex: 0x07080A)

    static let danger = Color(hex: 0xE0574A)
    static let good = Color(hex: 0x8FD6C1)

    static let corner: CGFloat = 14

    // Type. Bold condensed capitals, tight tracking.
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Big numerals that line up in a column.
    static func numerals(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight).width(.condensed).monospacedDigit()
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1
        )
    }

    /// "#3358a0" or "3358a0". Anything else is white, so a bad livery never blanks a view.
    init(hexString: String) {
        var text = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else {
            self.init(hex: 0xFFFFFF)
            return
        }
        self.init(hex: value)
    }
}

// MARK: - Stage layout

/// Where the panels live on a screen that has the machine behind it.
///
/// The owner played the first build and could not see his own customisations: the bot stood centre
/// left and the lists sat on top of it. So every screen with the bot behind it now keeps the LEFT
/// side clear and puts its panels in one column on the right, and tells the arena to frame the
/// machine at `botFrame` across the screen instead of dead centre.
enum StageLayout {

    /// Where the stage centre lands across the screen: 0 is the left edge, 1 the right.
    /// `ArenaHost.sendWorkshopConfig(_:mode:frame:)` passes it to the arena as `frame`.
    static let botFrame: Double = 0.28

    /// How much of the width the panel column may take. The other 45 % is the machine.
    static let columnFraction: CGFloat = 0.55

    /// The panel column's width for a given available width. Floored so the smallest landscape
    /// iPhone (667 x 375 pt, which iOS 18 still reaches) keeps a usable list rather than a sliver.
    static func columnWidth(_ available: CGFloat) -> CGFloat {
        let ideal = available * columnFraction
        return max(280, min(430, ideal.rounded()))
    }
}

/// A clear sheet that eats touches. The one Godot view now takes touches on the stage screens so
/// the turntable can be orbited (brief section 11), which means a screen that must NOT be orbited
/// through has to say so. Put this behind that screen's panels rather than turning the surface off:
/// the surface is shared with every other screen.
struct StageTouchBlocker: View {
    var body: some View {
        SwiftUI.Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .allowsHitTesting(true)
    }
}

// MARK: - Headings

/// A section heading: small, wide, faint capitals.
struct StageHeading: View {
    let text: String
    var tint: Color = Stage.textFaint

    init(_ text: String, tint: Color = Stage.textFaint) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text.uppercased())
            .font(Stage.label(11, weight: .bold))
            .kerning(1.6)
            .foregroundStyle(tint)
    }
}

// MARK: - Glass

/// A translucent dark glass panel with a thin light edge. Everything on the stage sits in one.
struct GlassPanel<Content: View>: View {
    var padding: CGFloat = 16
    var corner: CGFloat = Stage.corner
    var deep: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(deep ? Stage.panelDeep : Stage.panel)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Stage.edge, lineWidth: 1)
            }
    }
}

// MARK: - Buttons

struct StageButtonStyle: ButtonStyle {

    enum Kind {
        /// White fill, dark type. The one call to action on a screen.
        case primary
        /// Bare white capitals with a thin edge, for a dark part of the stage.
        case bare
        /// On glass, for anywhere the stage is bright (the dry ice at the bottom right).
        case glass
        /// A destructive action.
        case danger
        /// A small quiet action in a row of controls.
        case quiet
    }

    var kind: Kind = .bare
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && enabled
        return configuration.label
            .font(Stage.display(kind == .quiet ? 13 : 17))
            .kerning(kind == .quiet ? 1.0 : 1.6)
            .textCase(.uppercase)
            .foregroundStyle(foreground(pressed: pressed))
            .frame(maxWidth: .infinity)
            .padding(.vertical, kind == .quiet ? 9 : 13)
            .padding(.horizontal, 14)
            .background(background(pressed: pressed))
            .overlay {
                RoundedRectangle(cornerRadius: Stage.corner, style: .continuous)
                    .strokeBorder(edge(pressed: pressed), lineWidth: kind == .primary ? 0 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Stage.corner, style: .continuous))
            .scaleEffect(pressed ? 0.985 : 1)
            .opacity(enabled ? 1 : 0.38)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }

    private func foreground(pressed: Bool) -> Color {
        switch kind {
        case .primary: return Color.black
        case .danger: return pressed ? Color.white : Stage.danger
        default: return pressed ? Color.white : Stage.text
        }
    }

    @ViewBuilder
    private func background(pressed: Bool) -> some View {
        switch kind {
        case .primary:
            RoundedRectangle(cornerRadius: Stage.corner, style: .continuous)
                .fill(pressed ? Color.white.opacity(0.86) : Color.white)
        case .bare, .quiet:
            RoundedRectangle(cornerRadius: Stage.corner, style: .continuous)
                .fill(Color.white.opacity(pressed ? 0.22 : 0.06))
        case .glass:
            RoundedRectangle(cornerRadius: Stage.corner, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay {
                    RoundedRectangle(cornerRadius: Stage.corner, style: .continuous)
                        .fill(Color.black.opacity(pressed ? 0.24 : 0.42))
                }
        case .danger:
            RoundedRectangle(cornerRadius: Stage.corner, style: .continuous)
                .fill(pressed ? Stage.danger.opacity(0.85) : Color.white.opacity(0.05))
        }
    }

    private func edge(pressed: Bool) -> Color {
        switch kind {
        case .primary: return .clear
        case .danger: return Stage.danger.opacity(pressed ? 0.9 : 0.55)
        default: return pressed ? Stage.edgeBright : Stage.edge
        }
    }
}

/// A stage button. Bold condensed capitals, thin light edge, a pressed state that lifts the fill.
/// Give it a `focusID` and a game pad can land on it: the ring only appears once a pad has been
/// used, so a touch player never sees it.
struct StageButton: View {
    let title: String
    var kind: StageButtonStyle.Kind = .bare
    var enabled: Bool = true
    var focusID: String? = nil
    var action: () -> Void

    init(
        _ title: String,
        kind: StageButtonStyle.Kind = .bare,
        enabled: Bool = true,
        focusID: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.enabled = enabled
        self.focusID = focusID
        self.action = action
    }

    private var focused: Bool {
        guard let focusID else { return false }
        return PadFocus.shared.isFocused(focusID)
    }

    var body: some View {
        Button(action: { if enabled { action() } }) {
            Text(title)
        }
        .buttonStyle(StageButtonStyle(kind: kind, enabled: enabled))
        .disabled(!enabled)
        .overlay {
            RoundedRectangle(cornerRadius: Stage.corner, style: .continuous)
                .strokeBorder(Stage.text, lineWidth: focused ? 2.5 : 0)
                .opacity(focused ? 1 : 0)
                .padding(-2)
                .animation(.easeOut(duration: 0.12), value: focused)
        }
        .accessibilityLabel(title)
    }
}

// MARK: - Stat pips

/// Five pips, filled to the part's score. The numbers come from the catalogue, scaled across the
/// catalogue's own range, so a five really is the best in the list.
struct StatPips: View {
    let label: String
    let filled: Int
    var tint: Color = Stage.text
    var width: CGFloat = 54

    var body: some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(Stage.label(10, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(Stage.textFaint)
                .frame(width: width, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(index <= filled ? tint : Color.white.opacity(0.14))
                        .frame(width: 9, height: 5)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(filled) of 5")
    }
}

// MARK: - Weight bar

/// Used of the budget. Red the moment it goes over, and it says by how much.
struct WeightBar: View {
    let used: Double
    var budget: Double = BuildRules.budget
    var compact: Bool = false

    private var over: Bool { used > budget + 0.0001 }
    private var fraction: Double { budget > 0 ? min(1.4, used / budget) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(BuildRules.number(used))
                    .font(Stage.numerals(compact ? 20 : 26))
                    .foregroundStyle(over ? Stage.danger : Stage.text)
                Text("of \(BuildRules.number(budget)) kg")
                    .font(Stage.label(compact ? 11 : 13))
                    .foregroundStyle(Stage.textDim)
                Spacer(minLength: 6)
                Text(over ? "Over by \(BuildRules.kilograms(used - budget))" : "\(BuildRules.kilograms(budget - used)) spare")
                    .font(Stage.label(compact ? 10 : 12))
                    .foregroundStyle(over ? Stage.danger : Stage.textDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.12))
                    Capsule(style: .continuous)
                        .fill(over ? Stage.danger : Color.white.opacity(0.88))
                        .frame(width: max(2, proxy.size.width * min(1, fraction)))
                    if over {
                        Capsule(style: .continuous)
                            .stroke(Stage.danger, lineWidth: 1)
                    }
                }
            }
            .frame(height: compact ? 5 : 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weight \(BuildRules.number(used)) of \(BuildRules.number(budget)) kilograms")
    }
}

// MARK: - Small pieces

/// A label and a value on one line, the way the panels print numbers.
struct StageStat: View {
    let label: String
    let value: String
    var tint: Color = Stage.text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .font(Stage.label(10, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(Stage.textFaint)
            Spacer(minLength: 4)
            Text(value)
                .font(Stage.numerals(13))
                .foregroundStyle(tint)
        }
    }
}

/// The livery swatch that marks which bot you are looking at.
struct LiverySwatch: View {
    let hex: String
    var size: CGFloat = 14
    var selected: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(hexString: hex))
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(selected ? Color.white : Stage.edge, lineWidth: selected ? 2 : 1)
            }
    }
}

/// A row in a picker list: name, weight, pips, blurb, and a tick when it is the fitted part.
struct PartRow<Detail: View>: View {
    let name: String
    let weight: Double
    let blurb: String
    let selected: Bool
    var affordable: Bool = true
    @ViewBuilder var detail: Detail
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name.uppercased())
                        .font(Stage.display(15))
                        .kerning(0.8)
                        .foregroundStyle(selected ? Stage.text : Stage.textDim)
                    Spacer(minLength: 6)
                    Text(BuildRules.kilograms(weight))
                        .font(Stage.numerals(13))
                        .foregroundStyle(affordable ? Stage.textDim : Stage.danger)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(Stage.text)
                    }
                }
                detail
                if !blurb.isEmpty {
                    Text(blurb)
                        .font(Stage.body(11))
                        .foregroundStyle(Stage.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.12) : Color.white.opacity(0.03))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Stage.edgeBright : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

/// A segmented row of bold condensed capitals, used for the builder's tabs and for materials.
struct StageSegments<Value: Hashable>: View {
    let values: [Value]
    let title: (Value) -> String
    @Binding var selection: Value
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 4) {
            ForEach(values, id: \.self) { value in
                let isOn = value == selection
                Button {
                    selection = value
                } label: {
                    Text(title(value).uppercased())
                        .font(Stage.display(size))
                        .kerning(0.8)
                        .foregroundStyle(isOn ? Color.black : Stage.textDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isOn ? Color.white : Color.white.opacity(0.06))
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
