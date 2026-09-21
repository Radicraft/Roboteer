//
//  DesignSystem.swift
//  The Broadcast system (docs/design-system.md, owner's choice 2026-09-16), in Swift.
//
//  The game presents itself as a televised championship. Menus are the broadcast package, the
//  fight is the live feed, the career is the season coverage. This file is the ONE source of
//  colour, type and shape for every screen: no screen defines its own.
//
//  Sections 1 to 3 of the spec are implemented here: the tokens, the shapes (panel, lower third,
//  score bug, rule, ticker, button) and the motion (0.25 s in, 0.18 s out, a 0.15 s selection
//  sweep, numbers counting over 0.4 s). Section 5 is how each screen uses them.
//

import SwiftUI
import UIKit
import CoreText

// MARK: - Tokens (spec section 1)

enum Stage {

    // The Broadcast palette. No other hue appears in chrome.

    /// Page and fight backdrop behind glass.
    static let ink = Color(hex: 0x07090C)
    /// Panel fill.
    static let glass = Color(hex: 0x0E1218).opacity(0.82)
    /// Panel fill over the live arena, where the picture has to stay readable.
    static let glassOverArena = Color(hex: 0x0E1218).opacity(0.62)
    /// A deeper glass, for a panel that has to be read over the brightest part of the stage.
    static let glassDeep = Color(hex: 0x0E1218).opacity(0.93)
    /// The 1 px inner edge on every panel, top and left only.
    static let glassEdge = Color.white.opacity(0.10)
    /// Hairline rules, selection sweep, focus ring, the score bug rim.
    static let line = Color(hex: 0x35D6F0)
    /// Secondary rules and dividers.
    static let lineDim = Color(hex: 0x35D6F0).opacity(0.45)
    /// Primary text.
    static let type = Color(hex: 0xF4F6F8)
    /// Secondary text, labels, units.
    static let typeDim = Color(hex: 0x9CA6B2)
    /// Scrap numbers and the purse. The only warm chrome colour.
    static let scrap = Color(hex: 0xF0B23A)
    /// Damage, zone warning, losing states, quit.
    static let danger = Color(hex: 0xE5483C)
    /// Won states only, never chrome.
    static let win = Color(hex: 0x5BE38F)

    // The names the screens were written against, pointed at the Broadcast tokens so one file
    // still decides what every screen looks like.

    static let text = type
    static let textDim = typeDim
    static let textFaint = Color(hex: 0x9CA6B2).opacity(0.72)
    static let edge = glassEdge
    /// A bright edge means "this one is selected", and selection is `line` in this system.
    static let edgeBright = line
    static let panel = glass
    static let panelDeep = glassDeep
    static let ground = ink
    /// Scrap, and nothing else. Kept under the old name so no screen had to be rewritten to find it.
    static let gold = scrap
    static let good = win

    /// Corner cuts are 10 pt everywhere (spec section 1).
    static let corner: CGFloat = 10

    /// The 4 pt grid.
    enum Space {
        static let panelPadding: CGFloat = 12
        static let panelGap: CGFloat = 8
        static let gutter: CGFloat = 16
    }

    /// Lower thirds lean right by 12 degrees, always.
    static let skew: CGFloat = 0.2126  // tan(12 degrees)

    // MARK: Type (spec section 1)

    /// Display: 800 italic capitals, tracking -1 %.
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        BroadcastType.font(.display, size: size)
    }

    /// Title: 800 italic capitals at 28, tracking -0.5 %.
    static func title(_ size: CGFloat = 28) -> Font {
        BroadcastType.font(.display, size: size)
    }

    /// Button: 700 capitals, tracking +6 %.
    static func button(_ size: CGFloat = 17) -> Font {
        BroadcastType.font(.label, size: size)
    }

    /// Label: 700 capitals, tracking +10 %. Never below 11 pt (spec section 7).
    static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        BroadcastType.font(.label, size: max(BroadcastType.labelFloor, size))
    }

    /// Body: 500, sentence case. Never below 13 pt (spec section 7).
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        BroadcastType.font(.body, size: max(BroadcastType.bodyFloor, size))
    }

    /// 700 tabular figures, so columns of numbers line up.
    static func numerals(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        BroadcastType.font(.numerals, size: size)
    }

    /// The tracking each role carries, so a caller that wants the role's own spacing can ask for
    /// it rather than guessing. Screens that pass their own `kerning` still win.
    enum Tracking {
        static func display(_ size: CGFloat) -> CGFloat { -0.01 * size }
        static func button(_ size: CGFloat) -> CGFloat { 0.06 * size }
        static func label(_ size: CGFloat) -> CGFloat { 0.10 * size }
    }
}

// MARK: - Barlow Condensed

/// Barlow Condensed (SIL OFL), bundled in `Roboteer/Fonts` and registered at launch.
///
/// The faces are looked up by their PostScript names. If the family is not in the build (agent V1
/// produces the TTFs; a build taken before they land has an empty `Fonts` folder) every role falls
/// back to the system condensed face at the same weight, which keeps every screen legible and the
/// layout the same shape. `BroadcastType.usingBundledFamily` says which of the two you are looking
/// at, and the menu prints it in the quiet corner line so a screenshot is never ambiguous.
enum BroadcastType {

    /// The legibility floors from spec section 7.
    static let labelFloor: CGFloat = 11
    static let bodyFloor: CGFloat = 13

    enum Role {
        /// 800 italic, display and titles.
        case display
        /// 700, buttons and labels.
        case label
        /// 500, body copy.
        case body
        /// 700 with tabular figures.
        case numerals
    }

    private static let displayFace = "BarlowCondensed-ExtraBoldItalic"
    private static let boldFace = "BarlowCondensed-Bold"
    private static let mediumFace = "BarlowCondensed-Medium"

    /// Every face the app ships, by PostScript name. Also what `UIAppFonts` lists.
    static let faces = [displayFace, boldFace, mediumFace]

    /// True once the bundled family has been found. Read after `register()`.
    private(set) static var usingBundledFamily = false

    /// Registers every font file in the bundle, wherever it sits, then checks the family is
    /// really there. Called once at launch from `RoboteerApp`.
    ///
    /// The Info.plist lists the same files; registering by hand as well costs nothing and means a
    /// font that arrives in a folder reference rather than at the top of the bundle still loads.
    static func register() {
        var urls: [URL] = []
        for directory in [nil, "Fonts"] as [String?] {
            for ext in ["ttf", "otf"] {
                urls += Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: directory) ?? []
            }
        }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        usingBundledFamily = UIFont(name: displayFace, size: 12) != nil
            && UIFont(name: boldFace, size: 12) != nil
            && UIFont(name: mediumFace, size: 12) != nil
    }

    /// One line for the diagnostics corner: which family the screen you are looking at is set in.
    static var familyNote: String {
        usingBundledFamily ? "Barlow Condensed." : "System condensed, Barlow not in this build."
    }

    private static var cache: [String: Font] = [:]

    static func font(_ role: Role, size: CGFloat) -> Font {
        let key = "\(role)-\(size)"
        if let hit = cache[key] { return hit }
        let made = make(role, size: size)
        cache[key] = made
        return made
    }

    private static func make(_ role: Role, size: CGFloat) -> Font {
        switch role {
        case .display:
            if let ui = UIFont(name: displayFace, size: size) { return Font(ui) }
            return .system(size: size, weight: .heavy).width(.condensed).italic()
        case .label:
            if let ui = UIFont(name: boldFace, size: size) { return Font(ui) }
            return .system(size: size, weight: .bold).width(.condensed)
        case .body:
            if let ui = UIFont(name: mediumFace, size: size) { return Font(ui) }
            return .system(size: size, weight: .medium).width(.condensed)
        case .numerals:
            let base = UIFont(name: boldFace, size: size)
                ?? UIFont.systemFont(ofSize: size, weight: .bold)
            return Font(tabular(base))
        }
    }

    /// Tabular figures. `Font.monospacedDigit()` only speaks for the system family, so the feature
    /// is set on the descriptor instead and works for Barlow too.
    private static func tabular(_ base: UIFont) -> UIFont {
        let feature: [UIFontDescriptor.FeatureKey: Int] = [
            .type: kNumberSpacingType,
            .selector: kMonospacedNumbersSelector
        ]
        let descriptor = base.fontDescriptor.addingAttributes([.featureSettings: [feature]])
        return UIFont(descriptor: descriptor, size: base.pointSize)
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

// MARK: - Shapes (spec section 2)

/// A rectangle with one cut corner, top right, at the same angle everywhere. **There are no
/// rounded rectangles in this system**: every plate, chip, row and badge in the app is one of
/// these, which is why the cut is taken as a nominal size and clamped rather than being a free
/// parameter a screen can drift on.
struct CutRect: InsettableShape {

    var nominal: CGFloat
    var insetAmount: CGFloat = 0

    init(_ nominal: CGFloat = Stage.corner) {
        self.nominal = nominal
    }

    func inset(by amount: CGFloat) -> CutRect {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let cut = min(min(Stage.corner, max(4, nominal)), min(r.width * 0.35, r.height * 0.5))
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - cut, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY + cut))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        path.closeSubpath()
        return path
    }
}

/// The lower third: a plate skewed 12 degrees, leaning right.
struct LowerThirdShape: Shape {
    /// Leave room on the leading edge for the bar, which is drawn as its own shape.
    var barWidth: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let lean = rect.height * Stage.skew
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + lean + barWidth, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - lean, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + barWidth, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The 3 pt bar on a lower third's leading edge, skewed with it.
struct LowerThirdBarShape: Shape {
    var width: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        let lean = rect.height * Stage.skew
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + lean, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + lean + width, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + width, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Panel (spec section 2)

/// The chrome every panel wears: `glass` fill, a `glassEdge` inner edge on the top and the left
/// only, one cut corner top right, and a `line` hairline along the bottom.
struct PanelChrome: View {

    var cut: CGFloat = Stage.corner
    var fill: Color = Stage.glass
    /// A panel over the live arena is lighter, so the machine behind it still reads.
    var overArena: Bool = false
    /// The bottom hairline. Dimmed for a panel inside another panel.
    var rule: Color = Stage.line

    var body: some View {
        let shape = CutRect(cut)
        ZStack {
            shape.fill(overArena ? Stage.glassOverArena : fill)
            // Top and left only: the cut corner and the bottom rule do the other two sides.
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 10_000, y: 0))
            }
            .stroke(Stage.glassEdge, lineWidth: 1)
            .mask(shape)
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 10_000))
            }
            .stroke(Stage.glassEdge, lineWidth: 1)
            .mask(shape)
            VStack {
                Spacer(minLength: 0)
                Rectangle().fill(rule).frame(height: 1)
            }
            .mask(shape)
        }
        .allowsHitTesting(false)
    }
}

/// A panel. Everything on a screen sits in one.
struct Panel<Content: View>: View {
    var padding: CGFloat = Stage.Space.panelPadding
    var cut: CGFloat = Stage.corner
    var deep: Bool = false
    var overArena: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background { PanelChrome(cut: cut, fill: deep ? Stage.glassDeep : Stage.glass, overArena: overArena) }
    }
}

/// The name the screens were written against. One panel, one shape, one file.
struct GlassPanel<Content: View>: View {
    var padding: CGFloat = 16
    var corner: CGFloat = Stage.corner
    var deep: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        Panel(padding: padding, cut: corner, deep: deep) { content }
    }
}

// MARK: - Lower third (spec section 2)

/// A panel skewed 12 degrees with a 3 pt bar on its leading edge. Names, card headers, the result
/// banner and every stat strip are one of these.
struct LowerThird<Content: View>: View {

    var bar: Color = Stage.line
    var fill: Color = Stage.glass
    /// Lower thirds enter from the edge they belong to (spec section 3).
    var entersFrom: Edge? = nil
    var padding: EdgeInsets = EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 12)
    /// Extra room on the leading edge, because the 12 degree lean eats into it.
    var leanInset: CGFloat = 10
    @ViewBuilder var content: Content

    @State private var arrived = false

    var body: some View {
        content
            .padding(padding)
            // The lean eats into the leading edge, so the copy is pushed clear of it.
            .padding(.leading, leanInset)
            .background {
                ZStack {
                    LowerThirdShape(barWidth: 3).fill(fill)
                    LowerThirdShape(barWidth: 3)
                        .stroke(Stage.glassEdge, lineWidth: 1)
                    LowerThirdBarShape().fill(bar)
                }
                .allowsHitTesting(false)
            }
            .offset(x: offset)
            .opacity(entersFrom == nil || arrived ? 1 : 0)
            .onAppear {
                guard entersFrom != nil, !arrived else { return }
                withAnimation(.easeOut(duration: 0.25)) { arrived = true }
            }
    }

    private var offset: CGFloat {
        guard let entersFrom, !arrived else { return 0 }
        switch entersFrom {
        case .leading: return -40
        case .trailing: return 40
        default: return 0
        }
    }
}

// MARK: - Score bug (spec section 2)

/// A small unskewed panel with a `line` rim, numerals inside and a label above. Scrap, the fight
/// clock and the tier badge are score bugs.
struct ScoreBug: View {

    let label: String
    let value: String
    var tint: Color = Stage.type
    var size: CGFloat = 22
    /// A bug that is the live one on its strip.
    var lit: Bool = false
    var dim: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(Stage.label(11))
                .kerning(Stage.Tracking.label(11))
                .foregroundStyle(dim ? Stage.textFaint : Stage.typeDim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(Stage.numerals(size))
                .foregroundStyle(dim ? Stage.textFaint : tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            ZStack {
                CutRect(8).fill(lit ? Stage.line.opacity(0.18) : Stage.glass)
                CutRect(8).strokeBorder(lit ? Stage.line : Stage.lineDim, lineWidth: 1)
            }
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Rule (spec section 2)

/// 1 px `lineDim`, never thicker, never a box.
struct HairRule: View {
    var tint: Color = Stage.lineDim
    var body: some View {
        Rectangle()
            .fill(tint)
            .frame(height: 1)
            .allowsHitTesting(false)
    }
}

/// The spec's name for the same hairline.
typealias Rule = HairRule

// MARK: - Ticker (spec section 2 and 3)

/// The full width strip at the bottom of a broadcast screen: one line at a time, sliding in from
/// the right edge at 120 pt per second, the next waiting for the one before it to clear.
struct Ticker: View {

    let lines: [String]
    var height: CGFloat = 22
    /// How far in from the plate's own edge the words start, for a strip that runs under the
    /// screen's corners.
    var textInset: CGFloat = 0

    @State private var index = 0

    var body: some View {
        GeometryReader { proxy in
            if !lines.isEmpty {
                TickerLine(
                    text: lines[index % lines.count],
                    width: max(0, proxy.size.width - textInset),
                    onDone: { index += 1 }
                )
                .id(index)
                .padding(.leading, textInset)
            }
        }
        .frame(height: height)
        // The plate runs to the screen edges even though the words stay inside the safe area: a
        // ticker that stops short of the corners reads as a floating box rather than a strip.
        .background { Stage.ink.opacity(0.9).ignoresSafeArea() }
        .overlay(alignment: .top) { HairRule() }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct TickerLine: View {

    let text: String
    let width: CGFloat
    var speed: CGFloat = 120
    var onDone: () -> Void

    @State private var offset: CGFloat = 0
    @State private var started = false

    var body: some View {
        Text(text.uppercased())
            .font(Stage.label(12))
            .kerning(Stage.Tracking.label(12))
            .foregroundStyle(Stage.type)
            .lineLimit(1)
            .fixedSize()
            .background {
                GeometryReader { proxy in
                    Color.clear.onAppear { start(textWidth: proxy.size.width) }
                }
            }
            .offset(x: offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func start(textWidth: CGFloat) {
        guard !started, width > 0, textWidth > 0 else { return }
        started = true
        offset = width
        let distance = width + textWidth
        let duration = Double(distance / speed)
        DispatchQueue.main.async {
            withAnimation(.linear(duration: duration)) { offset = -textWidth }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { onDone() }
    }
}

// MARK: - Numbers that count (spec section 3)

/// Scrap and the purse count up over 0.4 s rather than appearing.
struct CountingNumber: View {
    let value: Int
    var font: Font = Stage.numerals(22)
    var tint: Color = Stage.scrap
    /// Straight to the number, for a row that is not the moment.
    var animated: Bool = true

    @State private var shown: Double = 0

    var body: some View {
        CountingText(value: shown)
            .font(font)
            .foregroundStyle(tint)
            .onAppear {
                guard animated else { shown = Double(value); return }
                withAnimation(.easeOut(duration: 0.4)) { shown = Double(value) }
            }
            .onChange(of: value) { _, newValue in
                withAnimation(.easeOut(duration: 0.4)) { shown = Double(newValue) }
            }
            .accessibilityLabel("\(value)")
    }
}

private struct CountingText: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View {
        Text("\(Int(value.rounded()))")
            .lineLimit(1)
    }
}

// MARK: - Buttons (spec section 2 and 3)

/// A button is a lower third. Selected or focused, the fill sweeps to `line` at 18 % from the
/// leading edge in 0.15 s and the bar goes to full. Pressed, the fill is `line` at 30 % and the
/// label is `ink`. Primary buttons are 1.5x the height of secondary ones. Danger swaps `line` for
/// `danger`. Nothing scales and nothing bounces.
struct BroadcastButtonStyle: ButtonStyle {

    enum Kind {
        /// The one call to action on a screen. 1.5x the height of the rest.
        case primary
        /// The ordinary button.
        case bare
        /// The same, for a part of the screen where the picture behind is bright.
        case glass
        /// A destructive action.
        case danger
        /// A small quiet action in a row of controls.
        case quiet
    }

    var kind: Kind = .bare
    var enabled: Bool = true
    var focused: Bool = false

    private var height: CGFloat {
        switch kind {
        case .primary: return 54
        case .quiet: return 30
        default: return 36
        }
    }

    private var accent: Color { kind == .danger ? Stage.danger : Stage.line }

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && enabled
        let size = kind == .primary ? 20 : (kind == .quiet ? 13 : 17)
        return configuration.label
            .font(Stage.button(CGFloat(size)))
            .kerning(Stage.Tracking.button(CGFloat(size)))
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(pressed ? Stage.ink : (kind == .danger ? Stage.danger : Stage.type))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            // Clear of the lean on the leading edge and of the cut on the trailing one.
            .padding(.leading, height * Stage.skew + 10)
            .padding(.trailing, 12)
            .background {
                plate(pressed: pressed)
            }
            .opacity(enabled ? 1 : 0.34)
            .animation(.easeOut(duration: 0.15), value: pressed)
            .animation(.easeOut(duration: 0.15), value: focused)
    }

    @ViewBuilder
    private func plate(pressed: Bool) -> some View {
        ZStack {
            LowerThirdShape(barWidth: 3)
                .fill(kind == .glass ? Stage.glassDeep : Stage.glass)
            // The selection sweep: `line` at 18 %, growing from the leading edge.
            LowerThirdShape(barWidth: 3)
                .fill(accent.opacity(pressed ? 0.30 : 0.18))
                .scaleEffect(x: pressed ? 1 : (focused ? 1 : 0), anchor: .leading)
            LowerThirdShape(barWidth: 3)
                .stroke(Stage.glassEdge, lineWidth: 1)
            LowerThirdBarShape(width: kind == .primary ? 4 : 3)
                .fill(accent.opacity(focused || pressed || kind == .primary ? 1 : 0.55))
        }
        .allowsHitTesting(false)
    }
}

/// The name the screens were written against.
typealias StageButtonStyle = BroadcastButtonStyle

/// A broadcast button. Give it a `focusID` and a game pad can land on it: the sweep and the focus
/// ring only appear once a pad has been used, so a touch player never sees them.
struct StageButton: View {
    let title: String
    var kind: BroadcastButtonStyle.Kind = .bare
    var enabled: Bool = true
    var focusID: String? = nil
    var action: () -> Void

    init(
        _ title: String,
        kind: BroadcastButtonStyle.Kind = .bare,
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
        .buttonStyle(BroadcastButtonStyle(kind: kind, enabled: enabled, focused: focused))
        .disabled(!enabled)
        .overlay {
            LowerThirdShape(barWidth: 3)
                .stroke(Stage.line, lineWidth: focused ? 2 : 0)
                .opacity(focused ? 1 : 0)
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
        .accessibilityLabel(title)
    }
}

/// The spec's name for the same button.
typealias BroadcastButton = StageButton

// MARK: - Stage layout

/// Where the panels live on a screen that has the machine behind it.
///
/// The owner played the first build and could not see his own customisations: the bot stood centre
/// left and the lists sat on top of it. So every screen with the bot behind it keeps the LEFT side
/// clear and puts its panels in one column on the right, and tells the arena to frame the machine
/// at `botFrame` across the screen instead of dead centre.
enum StageLayout {

    /// Where the stage centre lands across the screen: 0 is the left edge, 1 the right.
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

/// A section heading: small, wide capitals with the hairline under them.
struct StageHeading: View {
    let text: String
    var tint: Color = Stage.typeDim

    init(_ text: String, tint: Color = Stage.typeDim) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text.uppercased())
            .font(Stage.label(11))
            .kerning(Stage.Tracking.label(11))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

// MARK: - Stat pips

/// Five pips, filled to the part's score. The numbers come from the catalogue, scaled across the
/// catalogue's own range, so a five really is the best in the list.
struct StatPips: View {
    let label: String
    let filled: Int
    var tint: Color = Stage.line
    /// The LABEL's width. The pips add their own.
    var width: CGFloat = 54
    /// One pip's width. Narrower where six of these have to share a row with a portrait and a
    /// name, which is the scouting report.
    var pipWidth: CGFloat = 9
    var gap: CGFloat = 6

    var body: some View {
        HStack(spacing: gap) {
            Text(label.uppercased())
                .font(Stage.label(11))
                .kerning(Stage.Tracking.label(11))
                .foregroundStyle(Stage.textFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: width, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { index in
                    Rectangle()
                        .fill(index <= filled ? tint : Stage.type.opacity(0.14))
                        .frame(width: pipWidth, height: 4)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(filled) of 5")
    }
}

// MARK: - Weight bar

/// Used of the budget. Danger the moment it goes over, and it says by how much.
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
                    .foregroundStyle(over ? Stage.danger : Stage.type)
                Text("of \(BuildRules.number(budget)) kg")
                    .font(Stage.label(compact ? 11 : 13))
                    .foregroundStyle(Stage.typeDim)
                Spacer(minLength: 6)
                Text(over ? "Over by \(BuildRules.kilograms(used - budget))" : "\(BuildRules.kilograms(budget - used)) spare")
                    .font(Stage.label(11))
                    .foregroundStyle(over ? Stage.danger : Stage.typeDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Stage.type.opacity(0.12))
                    Rectangle()
                        .fill(over ? Stage.danger : Stage.line)
                        .frame(width: max(2, proxy.size.width * min(1, fraction)))
                }
            }
            .frame(height: compact ? 4 : 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weight \(BuildRules.number(used)) of \(BuildRules.number(budget)) kilograms")
    }
}

// MARK: - Small pieces

/// A label and a value on one line: the stat strip of spec section 2, drawn as a lower third.
struct StageStat: View {
    let label: String
    let value: String
    var tint: Color = Stage.type
    /// A strip that is one of a run down a panel keeps the bar quiet, so the run reads as a list.
    var bar: Color = Stage.lineDim

    var body: some View {
        LowerThird(bar: bar, fill: Stage.type.opacity(0.04), padding: EdgeInsets(top: 3, leading: 4, bottom: 3, trailing: 8), leanInset: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label.uppercased())
                    .font(Stage.label(11))
                    .kerning(Stage.Tracking.label(11))
                    .foregroundStyle(Stage.textFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text(value)
                    .font(Stage.numerals(15))
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The livery swatch that marks which bot you are looking at.
struct LiverySwatch: View {
    let hex: String
    var size: CGFloat = 14
    var selected: Bool = false

    var body: some View {
        CutRect(4)
            .fill(Color(hexString: hex))
            .frame(width: size, height: size)
            .overlay {
                CutRect(4)
                    .strokeBorder(selected ? Stage.line : Stage.glassEdge, lineWidth: selected ? 2 : 1)
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
    /// The manifest's glyph for this part, when one is drawn. Nothing else changes when it is
    /// absent: the name keeps its place and the row keeps its height.
    var glyph: GlyphArt? = nil
    @ViewBuilder var detail: Detail
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if glyph != nil {
                        GlyphMark(art: glyph, size: 17,
                                  tint: selected ? Stage.type : Stage.typeDim)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                    }
                    Text(name.uppercased())
                        .font(Stage.display(16))
                        .kerning(Stage.Tracking.display(16))
                        .foregroundStyle(selected ? Stage.type : Stage.typeDim)
                    Spacer(minLength: 6)
                    Text(BuildRules.kilograms(weight))
                        .font(Stage.numerals(13))
                        .foregroundStyle(affordable ? Stage.typeDim : Stage.danger)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(Stage.line)
                    }
                }
                detail
                if !blurb.isEmpty {
                    Text(blurb)
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background {
                ZStack {
                    CutRect(8).fill(selected ? Stage.line.opacity(0.14) : Stage.type.opacity(0.03))
                    CutRect(8).strokeBorder(selected ? Stage.line : Color.clear, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// A segmented row of capitals, used for the builder's tabs and for materials.
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
                        .font(Stage.label(max(11, size)))
                        .kerning(Stage.Tracking.label(max(11, size)))
                        .foregroundStyle(isOn ? Stage.type : Stage.typeDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            ZStack {
                                CutRect(6).fill(isOn ? Stage.line.opacity(0.18) : Stage.type.opacity(0.04))
                                CutRect(6).strokeBorder(isOn ? Stage.line : Color.clear, lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Hierarchy (spec section 8)

/// The tier strip as ONE LINE OF WORDS, never five boxes (spec section 8).
///
/// The current circuit is lit with a 2 pt `line` underline, a locked one is dim behind a lock
/// glyph, and the full game wall is a thin `line` marker standing between the last free circuit
/// and the first locked one. The screen hands over plain items, so the career is the only place
/// that has to know what a tier is.
struct TierLine: View {

    struct Item: Identifiable {
        let id: String
        let title: String
        var current: Bool = false
        var locked: Bool = false
        /// The full game wall stands immediately before this word.
        var wallBefore: Bool = false

        init(id: String, title: String, current: Bool = false, locked: Bool = false, wallBefore: Bool = false) {
            self.id = id
            self.title = title
            self.current = current
            self.locked = locked
            self.wallBefore = wallBefore
        }
    }

    let items: [Item]
    var size: CGFloat = 11

    var body: some View {
        HStack(alignment: .bottom, spacing: 13) {
            ForEach(items) { item in
                if item.wallBefore { wall }
                word(item)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("The five Series. You are in \(items.first { $0.current }?.title ?? "")")
    }

    /// The wall: a thin marker, not a plate and not a word.
    private var wall: some View {
        Rectangle()
            .fill(Stage.line)
            .frame(width: 2, height: size + 4)
            .accessibilityLabel("The full game starts here")
    }

    private func word(_ item: Item) -> some View {
        HStack(spacing: 3) {
            if item.locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: max(7, size - 3), weight: .bold))
                    .foregroundStyle(Stage.textFaint)
            }
            Text(item.title.uppercased())
                .font(Stage.label(item.current ? size + 1 : size))
                .kerning(Stage.Tracking.label(size))
                .foregroundStyle(item.current ? Stage.type : (item.locked ? Stage.textFaint : Stage.typeDim))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.bottom, 3)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Stage.line)
                .frame(height: 2)
                .opacity(item.current ? 1 : 0)
        }
    }
}

/// Navigation that is not the hero (spec section 8): label capitals, no plate, `typeDim` by
/// default, `line` when it leads somewhere important and `danger` when it costs scrap. A pad that
/// lands on it underlines it, which is the same mark the tier line uses for "you are here".
struct TextLink: View {

    let title: String
    var tint: Color = Stage.typeDim
    var size: CGFloat = 12
    var enabled: Bool = true
    var focusID: String? = nil
    var action: () -> Void

    init(
        _ title: String,
        tint: Color = Stage.typeDim,
        size: CGFloat = 12,
        enabled: Bool = true,
        focusID: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.tint = tint
        self.size = size
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
            Text(title.uppercased())
                .font(Stage.label(size))
                .kerning(Stage.Tracking.label(size))
                .foregroundStyle(focused ? Stage.type : tint)
                .lineLimit(1)
                .fixedSize()
                .padding(.vertical, 5)
                .padding(.horizontal, 2)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(focused ? Stage.type : tint)
                        .frame(height: 2)
                        .opacity(focused ? 1 : 0)
                }
                .contentShape(Rectangle())
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(.easeOut(duration: 0.15), value: focused)
        .accessibilityLabel(title)
    }
}

/// One clause of a money sentence: the words, then the number in the colour the number deserves.
struct MoneyClause {
    let lead: String
    let amount: Int
    /// `scrap` for money coming in, `danger` for money going out, `type` for money already paid.
    var tint: Color = Stage.scrap
    var tail: String = "."

    init(_ lead: String, _ amount: Int, tint: Color = Stage.scrap, tail: String = ".") {
        self.lead = lead
        self.amount = amount
        self.tint = tint
        self.tail = tail
    }
}

/// Money is a sentence, not a row of bugs (spec section 8): "Entry paid 120. The final pays 780.
/// Repairs owing 184." with ONLY the numbers coloured.
struct MoneySentence: View {

    let clauses: [MoneyClause]
    var size: CGFloat = 13
    /// The colour of the words. The numbers bring their own.
    var tint: Color = Stage.type

    init(_ clauses: [MoneyClause], size: CGFloat = 13, tint: Color = Stage.type) {
        self.clauses = clauses
        self.size = size
        self.tint = tint
    }

    var body: some View {
        sentence
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(spoken)
    }

    private var sentence: Text {
        var out = Text("")
        for (index, clause) in clauses.enumerated() {
            if index > 0 { out = out + word(" ") }
            if !clause.lead.isEmpty { out = out + word(clause.lead + " ") }
            out = out + Text("\(clause.amount)")
                .font(Stage.numerals(size))
                .foregroundStyle(clause.tint)
            if !clause.tail.isEmpty { out = out + word(clause.tail) }
        }
        return out
    }

    private func word(_ text: String) -> Text {
        Text(text)
            .font(Stage.body(size))
            .foregroundStyle(tint)
    }

    private var spoken: String {
        clauses.map { "\($0.lead) \($0.amount)\($0.tail)" }.joined(separator: " ")
    }
}

/// The one boxed panel's header: a label, with the part of it that changes lit.
struct PanelLabel: View {

    let label: String
    var accent: String = ""

    init(_ label: String, accent: String = "") {
        self.label = label
        self.accent = accent
    }

    var body: some View {
        (
            Text(label.uppercased())
                .foregroundStyle(Stage.typeDim)
            + Text(accent.isEmpty ? "" : " \(accent.uppercased())")
                .foregroundStyle(Stage.line)
        )
        .font(Stage.label(11))
        .kerning(Stage.Tracking.label(11))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

extension String {
    /// A catalogue name, in the case prose wants it. A name that arrives SHOUTING (an id with no
    /// catalogue entry behind it, which `CareerEngine.houseBotName` falls back to) is turned down;
    /// a name that is already written properly is left alone.
    var asName: String { self == uppercased() ? capitalized : self }
}

/// The back chevron: top left on a screen that has a way back, never a boxed button
/// (spec section 8).
struct BackChevron: View {

    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(Stage.typeDim)
                .frame(width: 32, height: 30, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

// MARK: - The asset manifest (spec section 6)

/// The raster art agent V1 produces into `Art/ui`, which ships as a folder reference and so lands
/// in the bundle under `ui/`.
///
/// Every lookup is allowed to fail: a build taken before the art lands shows the ink wash instead
/// and says nothing about it on screen. Panels, lower thirds, bugs, rules and buttons are DRAWN,
/// so no screen's chrome depends on any of this.
enum BroadcastArt {

    private static var cache: [String: UIImage?] = [:]

    static func image(_ name: String) -> UIImage? {
        if let hit = cache[name] { return hit }
        var found: UIImage?
        for directory in ["ui", nil] as [String?] {
            if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: directory),
               let image = UIImage(contentsOfFile: url.path) {
                found = image
                break
            }
        }
        cache[name] = found
        return found
    }

    /// The key art for a circuit, for a menu screen with no live machine on it.
    static func backdrop(tier: String) -> UIImage? { image("backdrop_\(tier)") }

    /// The main menu's own key art: dry ice, stage lights, an empty turntable.
    static var menuKeyArt: UIImage? { image("menu_keyart") }

    static func arenaCard(_ id: String) -> UIImage? { image("arena_\(id)") }
    static func boss(_ id: String) -> UIImage? { image("boss_\(id)") }
    static func rival(_ id: String) -> UIImage? { image("rival_\(id)") }
}

// MARK: - Wave P, post-match

/// A bar is a RULE that fills, never a pill (spec sections 2 and 8). The condition bars on the
/// match report and the Level bar on the rewards screen are the same 3 pt shape.
struct FillRule: View {

    /// 0 to 1.
    var fraction: Double
    var tint: Color = Stage.line
    var height: CGFloat = 3
    /// The unfilled part of the rule.
    var track: Color = Stage.type.opacity(0.14)

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(track)
                Rectangle()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
    }
}

/// One part's condition after a match (brief v5 section 5): the part's name, the bar, the
/// percentage. `line` while the part is sound, `scrap` once it is hurt, `danger` when it is nearly
/// gone, and the name and the number in `danger` too once the part is off the machine.
struct ConditionRow: View {

    let label: String
    /// 0 to 1 now.
    let condition: Double
    var barWidth: CGFloat = 52
    var size: CGFloat = 11

    private var value: Double { min(1, max(0, condition)) }
    private var gone: Bool { value <= 0.001 }
    private var percent: Int { Int((value * 100).rounded()) }

    private var tint: Color {
        if value < 0.25 { return Stage.danger }
        if value < 0.7 { return Stage.scrap }
        return Stage.line
    }

    var body: some View {
        HStack(spacing: 7) {
            Text(label.uppercased())
                .font(Stage.label(size))
                .kerning(Stage.Tracking.label(size))
                .foregroundStyle(gone ? Stage.danger : Stage.typeDim)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .leading)
            FillRule(fraction: value, tint: tint)
                .frame(width: barWidth)
            Text("\(percent)%")
                .font(Stage.numerals(12))
                .foregroundStyle(gone ? Stage.danger : Stage.type)
                .frame(width: 36, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(percent) percent")
    }
}

/// The rewards screen's Level bar (brief v5 section 6). It fills from where it stood before the
/// win to where it stands after it, over the same 0.4 s the money counts in. A win that crossed a
/// Level fills the bar to the end first, then starts the new Level from empty, so the crossing is
/// seen. (B2's `LevelBar` is the Series screen's static one: a label, a bar and the remainder.)
struct LevelGainBar: View {

    var from: Double
    var to: Double
    /// True when this win crossed at least one Level.
    var wraps: Bool = false
    var animated: Bool = true

    @State private var shown: Double = 0

    var body: some View {
        FillRule(fraction: shown, tint: Stage.line)
            .onAppear { run() }
    }

    private func run() {
        let start = min(1, max(0, from))
        let end = min(1, max(0, to))
        guard animated else { shown = end; return }
        shown = start
        guard wraps else {
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) { shown = end }
            return
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.2)) { shown = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            shown = 0
            withAnimation(.easeOut(duration: 0.4)) { shown = end }
        }
    }
}

/// One line of a ledger: the words on the left in label capitals, the number on the right in
/// `scrap`. A zero line is printed faint rather than hidden, so the four sources of scrap always
/// read in the same order (brief v5 section 6).
struct LedgerRow: View {

    let label: String
    let amount: Int
    var tint: Color = Stage.scrap
    /// Money counts up over 0.4 s (spec section 3).
    var counts: Bool = true
    var size: CGFloat = 14

    private var colour: Color { amount == 0 ? Stage.textFaint : tint }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label.uppercased())
                .font(Stage.label(11))
                .kerning(Stage.Tracking.label(11))
                .foregroundStyle(Stage.textFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 6)
            if counts && amount != 0 {
                CountingNumber(value: amount, font: Stage.numerals(size), tint: colour)
            } else {
                Text("\(amount)")
                    .font(Stage.numerals(size))
                    .foregroundStyle(colour)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(amount)")
    }
}

// MARK: - Wave P, series

/// The one continuous career bar (brief v5 section 7), drawn as a RULE and not as a panel: the
/// Level in label capitals, a 3 pt track that fills in `line`, and one quiet sentence saying what
/// the next Level costs. Option S1 of `docs/look/series-options.html` gives it the full width of
/// the screen under the Series words, where both progression tracks can be read in one glance.
struct LevelBar: View {

    let level: LevelState
    /// The right hand sentence is dropped on a narrow card, where the bar is a progress mark only.
    var showsRemainder: Bool = true

    private var remainder: String {
        guard !level.isCapped else { return "Level \(level.cap), the top of the ladder" }
        let left = max(1, level.pointsPerLevel - level.pointsIntoLevel)
        return "\(left) points to Level \(level.level + 1)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("LEVEL \(level.level)")
                .font(Stage.label(11))
                .kerning(Stage.Tracking.label(11))
                .foregroundStyle(Stage.type)
                .fixedSize()

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Stage.type.opacity(0.14))
                    Rectangle()
                        .fill(Stage.line)
                        .frame(width: max(0, min(1, level.fraction)) * proxy.size.width)
                }
            }
            .frame(height: 3)

            if showsRemainder {
                Text(remainder)
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.textFaint)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(level.level). \(remainder).")
    }
}

/// One cell of the Series strip and of the campaign board: a word, a quiet note under it, and a
/// 2 pt bar down the leading edge that carries the state. Never a box (design system section 8),
/// and the same cell in both places so the strip and the board cannot drift apart.
struct SlotCell: View {

    enum State {
        /// Won, and the campaign has moved past it.
        case won
        /// The match on duty.
        case next
        /// Won, and replayable now the campaign is finished.
        case replay
        /// Reached, but not fought yet.
        case waiting
        case locked
    }

    let head: String
    var note: String = ""
    var state: State = .waiting
    /// A cell that leads somewhere is a tap target.
    var action: (() -> Void)? = nil

    private var headTint: Color {
        switch state {
        case .won: return Stage.type
        case .next: return Stage.line
        case .replay: return Stage.type
        case .waiting: return Stage.typeDim
        case .locked: return Stage.textFaint
        }
    }

    private var barTint: Color {
        switch state {
        case .won, .next, .replay: return Stage.line
        case .waiting, .locked: return Stage.type.opacity(0.18)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(head.uppercased())
                .font(Stage.label(11))
                .kerning(Stage.Tracking.label(11))
                .foregroundStyle(headTint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !note.isEmpty {
                Text(note)
                    .font(Stage.label(11))
                    .foregroundStyle(Stage.textFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background {
            Rectangle().fill(state == .next ? Stage.line.opacity(0.12) : Color.clear)
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(barTint).frame(width: 2)
        }
        .opacity(state == .locked ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture { action?() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(action == nil ? [] : .isButton)
    }
}

// MARK: - Wave P, agent H: the drawn art on the screens

/// One SVG glyph from the asset manifest (design system section 6), parsed into paths.
///
/// `UIImage` cannot read an SVG, and the glyphs have to tint (`type` on a row, `ink` on a
/// pressed disc) and stay crisp at any size, so they are parsed once and drawn with `Canvas`.
/// The subset is the one every file in `Art/ui` uses and nothing else: a single `<g>` carrying
/// `transform="translate(tx,ty) scale(s)"`, `fill`, `stroke` and `stroke-width`, holding
/// `<path d="...">` with absolute `M`, `L`, `C` and `Z`, and `<rect>`. Anything outside that
/// returns nil and the caller prints its word instead, which is what the arena does.
struct GlyphArt {

    struct Piece {
        let path: Path
        let filled: Bool
        let evenOdd: Bool
        /// In viewBox units; zero means the piece is not stroked.
        let strokeWidth: CGFloat
    }

    let pieces: [Piece]
    let viewBox: CGSize

    // MARK: Parsing

    static func parse(_ svg: String) -> GlyphArt? {
        let box = attribute("viewBox", in: svg).flatMap { text -> CGSize? in
            let parts = text.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
            guard parts.count == 4, parts[2] > 0, parts[3] > 0 else { return nil }
            return CGSize(width: parts[2], height: parts[3])
        } ?? CGSize(width: 64, height: 64)

        var pieces: [Piece] = []
        for group in elements(named: "g", in: svg) {
            let transform = affine(from: attribute("transform", in: group.open))
            let groupFill = attribute("fill", in: group.open)
            let groupStroke = attribute("stroke", in: group.open)
            let groupWidth = Double(attribute("stroke-width", in: group.open) ?? "") ?? 0

            for element in selfClosing(in: group.body) {
                var path: Path
                switch element.name {
                case "path":
                    guard let d = attribute("d", in: element.text) else { continue }
                    guard let parsed = pathData(d) else { return nil }
                    path = parsed
                case "rect":
                    let x = Double(attribute("x", in: element.text) ?? "") ?? 0
                    let y = Double(attribute("y", in: element.text) ?? "") ?? 0
                    let w = Double(attribute("width", in: element.text) ?? "") ?? 0
                    let h = Double(attribute("height", in: element.text) ?? "") ?? 0
                    let r = Double(attribute("rx", in: element.text) ?? "") ?? 0
                    guard w > 0, h > 0 else { continue }
                    path = Path(roundedRect: CGRect(x: x, y: y, width: w, height: h),
                                cornerRadius: r)
                default:
                    continue
                }
                path = path.applying(transform)

                let fill = attribute("fill", in: element.text) ?? groupFill
                let stroke = attribute("stroke", in: element.text) ?? groupStroke
                let width = Double(attribute("stroke-width", in: element.text) ?? "") ?? groupWidth
                let rule = attribute("fill-rule", in: element.text) ?? "nonzero"
                let scale = sqrt(abs(transform.a * transform.d - transform.b * transform.c))
                pieces.append(Piece(
                    path: path,
                    filled: (fill ?? "none").lowercased() != "none",
                    evenOdd: rule == "evenodd",
                    strokeWidth: (stroke ?? "none").lowercased() == "none"
                        ? 0 : CGFloat(width) * scale))
            }
        }
        return pieces.isEmpty ? nil : GlyphArt(pieces: pieces, viewBox: box)
    }

    /// `translate(a,b) scale(s)` and `scale(s)` are the only forms the manifest uses.
    private static func affine(from text: String?) -> CGAffineTransform {
        guard let text else { return .identity }
        var result = CGAffineTransform.identity
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "("), let close = rest[open...].firstIndex(of: ")") {
            let name = rest[rest.startIndex..<open].trimmingCharacters(in: .whitespaces)
            let numbers = rest[rest.index(after: open)..<close]
                .split(whereSeparator: { $0 == " " || $0 == "," })
                .compactMap { Double($0) }
            switch name {
            case "translate" where numbers.count >= 2:
                result = result.concatenating(
                    CGAffineTransform(translationX: numbers[0], y: numbers[1]))
            case "scale" where numbers.count >= 1:
                let sy = numbers.count >= 2 ? numbers[1] : numbers[0]
                result = CGAffineTransform(scaleX: numbers[0], y: sy).concatenating(result)
            default:
                break
            }
            rest = rest[rest.index(after: close)...]
        }
        return result
    }

    /// Absolute `M`, `L`, `C` and `Z`. Anything else gives nil, so a file this cannot read is
    /// never drawn half finished.
    private static func pathData(_ d: String) -> Path? {
        var path = Path()
        var numbers: [CGFloat] = []
        var command: Character = " "
        var start = CGPoint.zero
        var here = CGPoint.zero

        func flush() -> Bool {
            switch command {
            case "M":
                guard numbers.count >= 2, numbers.count % 2 == 0 else { return false }
                path.move(to: CGPoint(x: numbers[0], y: numbers[1]))
                start = CGPoint(x: numbers[0], y: numbers[1])
                here = start
                var i = 2
                while i + 1 < numbers.count {
                    here = CGPoint(x: numbers[i], y: numbers[i + 1])
                    path.addLine(to: here)
                    i += 2
                }
            case "L":
                guard numbers.count >= 2, numbers.count % 2 == 0 else { return false }
                var i = 0
                while i + 1 < numbers.count {
                    here = CGPoint(x: numbers[i], y: numbers[i + 1])
                    path.addLine(to: here)
                    i += 2
                }
            case "C":
                guard numbers.count >= 6, numbers.count % 6 == 0 else { return false }
                var i = 0
                while i + 5 < numbers.count {
                    here = CGPoint(x: numbers[i + 4], y: numbers[i + 5])
                    path.addCurve(to: here,
                                  control1: CGPoint(x: numbers[i], y: numbers[i + 1]),
                                  control2: CGPoint(x: numbers[i + 2], y: numbers[i + 3]))
                    i += 6
                }
            case "Z":
                guard numbers.isEmpty else { return false }
                path.closeSubpath()
                here = start
            case " ":
                return numbers.isEmpty
            default:
                return false
            }
            numbers.removeAll(keepingCapacity: true)
            return true
        }

        var token = ""
        func takeNumber() -> Bool {
            guard !token.isEmpty else { return true }
            guard let value = Double(token) else { return false }
            numbers.append(CGFloat(value))
            token = ""
            return true
        }

        for character in d {
            if character.isLetter && !(character == "e" && !token.isEmpty) {
                guard takeNumber(), flush() else { return nil }
                command = Character(character.uppercased())
                if character != "z" && character != "Z" && character.isLowercase { return nil }
            } else if character == " " || character == "," || character == "\n" || character == "\t" {
                guard takeNumber() else { return nil }
            } else if character == "-" && !token.isEmpty && !token.hasSuffix("e") {
                guard takeNumber() else { return nil }
                token = "-"
            } else {
                token.append(character)
            }
        }
        guard takeNumber(), flush() else { return nil }
        return path
    }

    // MARK: Tiny XML reader

    private static func attribute(_ name: String, in text: String) -> String? {
        guard let range = text.range(of: "\(name)=\"") else { return nil }
        let rest = text[range.upperBound...]
        guard let close = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[rest.startIndex..<close])
    }

    private static func elements(named name: String, in text: String)
        -> [(open: String, body: String)] {
        var found: [(String, String)] = []
        var rest = Substring(text)
        while let open = rest.range(of: "<\(name)"),
              let openEnd = rest[open.upperBound...].firstIndex(of: ">") {
            let openTag = String(rest[open.lowerBound...openEnd])
            let bodyStart = rest.index(after: openEnd)
            guard let close = rest[bodyStart...].range(of: "</\(name)>") else { break }
            found.append((openTag, String(rest[bodyStart..<close.lowerBound])))
            rest = rest[close.upperBound...]
        }
        return found
    }

    private static func selfClosing(in text: String) -> [(name: String, text: String)] {
        var found: [(String, String)] = []
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "<"), let close = rest[open...].firstIndex(of: ">") {
            let element = String(rest[open...close])
            let name = element.dropFirst().prefix { $0.isLetter }
            if !name.isEmpty { found.append((String(name), element)) }
            rest = rest[rest.index(after: close)...]
        }
        return found
    }
}

/// The glyphs from `Art/ui`, which ships as a folder reference and so lands under `ui/` in the
/// bundle. Parsed once each; a glyph nobody has drawn is nil and the caller says the word.
enum BroadcastGlyph {

    private static var cache: [String: GlyphArt?] = [:]

    static func named(_ name: String) -> GlyphArt? {
        if let hit = cache[name] { return hit }
        var found: GlyphArt?
        for directory in ["ui", nil] as [String?] {
            if let url = Bundle.main.url(forResource: name, withExtension: "svg",
                                         subdirectory: directory),
               let text = try? String(contentsOf: url, encoding: .utf8) {
                found = GlyphArt.parse(text)
                break
            }
        }
        cache[name] = found
        return found
    }

    /// A weapon's glyph is named for its PART id. Wave P's three new kinds have their own
    /// (`shock_prod`, `tesla_arc`, `drill_lance`); the other three new weapons share a kind with
    /// an older part, so they borrow that part's glyph rather than shipping a duplicate, which
    /// is exactly what `Arena/ui/controls.gd` does with the same catalogue.
    static func weapon(_ partID: String) -> GlyphArt? {
        if let own = named("glyph_weapon_\(partID)") { return own }
        guard let kind = Catalogue.shared.weapon(partID)?.kind else { return nil }
        for other in Catalogue.shared.weapons where other.kind == kind && other.id != partID {
            if let borrowed = named("glyph_weapon_\(other.id)") { return borrowed }
        }
        return nil
    }

    static func utility(_ partID: String) -> GlyphArt? { named("glyph_utility_\(partID)") }

    /// The Series marks on the campaign board. The badges are still named for the five tiers.
    static func series(_ tierID: String) -> GlyphArt? { named("tier_\(tierID)") }
}

/// A glyph drawn at a size, in one colour. Never a box and never a background: it is a mark
/// beside a word, the way the manifest's glyphs are used on the fight's own buttons.
struct GlyphMark: View {

    let art: GlyphArt?
    var size: CGFloat = 18
    var tint: Color = Stage.type

    var body: some View {
        Canvas { context, canvas in
            guard let art else { return }
            let scale = min(canvas.width / art.viewBox.width, canvas.height / art.viewBox.height)
            context.translateBy(x: (canvas.width - art.viewBox.width * scale) / 2,
                                y: (canvas.height - art.viewBox.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            for piece in art.pieces {
                if piece.filled {
                    context.fill(piece.path, with: .color(tint),
                                 style: FillStyle(eoFill: piece.evenOdd))
                }
                if piece.strokeWidth > 0 {
                    context.stroke(piece.path, with: .color(tint),
                                   style: StrokeStyle(lineWidth: piece.strokeWidth,
                                                      lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(width: size, height: size)
        .opacity(art == nil ? 0 : 1)
        .accessibilityHidden(true)
    }
}

/// A rival's or a boss's portrait: a plate of art with one cut corner, no panel round it.
/// Art supports the hero, it does not add a panel (spec section 8), so this is a picture and a
/// hairline and nothing else. A portrait nobody has drawn leaves the livery swatch alone.
struct PortraitPlate: View {

    let image: UIImage?
    var side: CGFloat = 54
    var tint: Color = Stage.lineDim

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: side, height: side)
                .clipShape(CutRect(8))
                .overlay { CutRect(8).strokeBorder(tint, lineWidth: 1) }
                .accessibilityHidden(true)
        }
    }
}

/// An arena card: the 16:9 key art for one arena, cut corner, with the arena's name over the
/// foot of it. Used on the Series card and in the quick fight's picker.
struct ArenaCard: View {

    let arenaID: String
    let name: String
    var width: CGFloat = 150
    /// The card's shape. 16:9 is the art's own; a picker with six of them on one sheet crops
    /// to a wider band so the rows below it keep their room.
    var aspect: CGFloat = 16 / 9
    var selected: Bool = false
    var focused: Bool = false
    var locked: Bool = false
    /// The word under the name: the hazard, or the reason it is locked.
    var note: String = ""

    private var height: CGFloat { (width / aspect).rounded() }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let art = BroadcastArt.arenaCard(arenaID) {
                Image(uiImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                Rectangle().fill(Stage.glass).frame(width: width, height: height)
            }
            LinearGradient(colors: [Stage.ink.opacity(0.1), Stage.ink.opacity(0.92)],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: width, height: height)
            VStack(alignment: .leading, spacing: 0) {
                Text(name.uppercased())
                    .font(Stage.display(15))
                    .kerning(Stage.Tracking.display(15))
                    .foregroundStyle(Stage.type)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !note.isEmpty {
                    Text(note)
                        .font(Stage.label(11))
                        .kerning(Stage.Tracking.label(11))
                        .foregroundStyle(locked ? Stage.line : Stage.textFaint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, 7)
            .padding(.bottom, 5)
        }
        .frame(width: width, height: height)
        .clipShape(CutRect(10))
        .overlay {
            // Only the chosen one wears the `line` colour, so a grid of six reads as one choice
            // rather than six half-made ones.
            CutRect(10).strokeBorder(
                focused ? Stage.type : (selected ? Stage.line : Stage.type.opacity(0.22)),
                lineWidth: focused || selected ? 2 : 1)
        }
        .saturation(locked ? 0.2 : 1)
        .opacity(locked ? 0.78 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(note.isEmpty ? name : "\(name). \(note)")
    }
}

/// The arena, as a lower third over its own key art: the band a broadcast puts across the foot of
/// the picture when it says where you are. Used inside the next-match card, where a 16:9 card
/// would cost the Series strip its room. Still one panel: this is art inside the card, not a
/// second box.
struct ArenaBand: View {

    let arenaID: String
    let name: String
    /// The one sentence over the art, after the arena's own name.
    let line: String
    /// Drawn against the trailing edge: the house bot on duty.
    var portrait: UIImage? = nil
    var height: CGFloat = 56

    var body: some View {
        ZStack(alignment: .leading) {
            if let art = BroadcastArt.arenaCard(arenaID) {
                Image(uiImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: height)
                    .clipped()
            } else {
                Rectangle().fill(Stage.type.opacity(0.04))
            }
            LinearGradient(colors: [Stage.ink.opacity(0.88), Stage.ink.opacity(0.35)],
                           startPoint: .leading, endPoint: .trailing)
            HStack(alignment: .center, spacing: 9) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name.uppercased())
                        .font(Stage.display(17))
                        .kerning(Stage.Tracking.display(17))
                        .foregroundStyle(Stage.type)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(line)
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.typeDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                if let portrait {
                    Image(uiImage: portrait)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: height - 10, height: height - 10)
                        .clipShape(CutRect(7))
                        .overlay { CutRect(7).strokeBorder(Stage.lineDim, lineWidth: 1) }
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, 9)
            .padding(.trailing, 5)
        }
        .frame(height: height)
        .clipShape(CutRect(8))
        .overlay(alignment: .leading) { Rectangle().fill(Stage.line).frame(width: 3) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name). \(line)")
    }
}
