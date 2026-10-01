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

    // WAVE C (owner, 2026-09-28): the menus are direction A, "Blueprint overlay"
    // (docs/look/menus-blueprint.html): every plate is blueprint blue graph paper in the icon's own
    // blue, the line is white, selection is a white wash, the one primary is a solid white plate
    // with blue stencil type. The Broadcast names below are kept, so every screen written against
    // them moves with the tokens; the values are direction A's. `Blueprint` holds the rest.

    /// Page and fight backdrop behind glass.
    static let ink = Color(hex: 0x07090C)
    /// Panel fill: the blueprint plate, rgba(14, 58, 140, 0.9).
    static let glass = Blueprint.plate
    /// Panel fill over the live arena. Direction A uses the one plate everywhere.
    static let glassOverArena = Blueprint.plate
    /// The deep plate: the secondary button's navy, for a sheet over the brightest stage.
    static let glassDeep = Blueprint.secondary
    /// The 1 px inner edge on every panel, top and left only.
    static let glassEdge = Color.white.opacity(0.10)
    /// The drawing line: fill bars, gauges, leader lines and accent words. White in direction A.
    static let line = Color.white
    /// Dim fill bars.
    static let lineDim = Color.white.opacity(0.45)
    /// Primary text.
    static let type = Color(hex: 0xF4F6F8)
    /// Secondary text, labels, units.
    static let typeDim = Blueprint.dim
    /// Scrap numbers and the purse. Direction A sets money in white figures like every other number;
    /// the token is kept so a screen can still say "this is money".
    static let scrap = Color.white
    /// Damage, zone warning, losing states, quit. Direction A's danger, readable on the blue.
    static let danger = Blueprint.danger
    /// Won states only, never chrome.
    static let win = Color(hex: 0x5BE38F)

    // OWNER RULE (2026-09-21, restated 2026-09-24): NO line accents. No coloured edge strokes,
    // no leading bars, no diagonal accent lines, no frames round a selected row, anywhere in the
    // app. Emphasis comes from weight, fill, type, the plain upright plate and light. These are the
    // tokens that carry it instead.

    /// The soft light across the top of every plate: how a plate reads as a raised object
    /// without a line round it.
    /// Direction A's plates are flat paper: the grid is their texture, not a light.
    static let topLight = LinearGradient(
        colors: [Color.white.opacity(0.0), Color.white.opacity(0.0)],
        startPoint: .top, endPoint: .center)
    /// A selected row or segment: a white wash, never a frame.
    static let selectedFill = Blueprint.selected
    /// The one neutral divider between sections of a panel, and the rule between table rows.
    static let divider = Blueprint.rule2
    /// The primary call to action's plate: solid white, blue stencil type on it.
    static let primaryFill = Blueprint.primary

    // The names the screens were written against, pointed at the Broadcast tokens so one file
    // still decides what every screen looks like.

    static let text = type
    static let textDim = typeDim
    static let textFaint = Color.white.opacity(0.5)
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

    // There is no lean: lower thirds stand upright (wave E, owner rule, no skewed or slanted
    // accents). `skew` was deleted so nothing can lean a plate again.

    // MARK: Type (spec section 1)

    /// Display: Saira Stencil One, capitals, tracking +1 %. Callers ask for the size the
    /// old Barlow 800 italic wanted; `BroadcastType` sets the stencil at 0.8 of it.
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        BroadcastType.font(.display, size: size)
    }

    /// Title: the display face at 28.
    static func title(_ size: CGFloat = 28) -> Font {
        BroadcastType.font(.display, size: size)
    }

    /// Button: Saira Semi Condensed 700 capitals, tracking +6 %.
    static func button(_ size: CGFloat = 17) -> Font {
        BroadcastType.font(.label, size: size)
    }

    /// Label: Saira Semi Condensed 700 capitals, tracking +8 %. Never below 11 pt (spec section 7).
    static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        BroadcastType.font(.label, size: max(BroadcastType.labelFloor, size))
    }

    /// Body: Saira Semi Condensed 500, sentence case. Never below 13 pt (spec section 7).
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        BroadcastType.font(.body, size: max(BroadcastType.bodyFloor, size))
    }

    /// Figures: Saira Semi Condensed 700 with its tabular figures (`tnum`), so columns line up
    /// and a counting number never jitters, while ".", ":" and "," keep their own narrow widths.
    static func numerals(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        BroadcastType.font(.numerals, size: size)
    }

    /// A value that is usually a figure but is sometimes a word ("Arcade", "None listed"): the
    /// numbers face when the text is a figure (digits with at most a unit or two of letters, such as
    /// "100 KG", "3:00" or "LV 20"), the label face when it is a word. Both are the UI face; a figure
    /// is drawn a little taller (see `BroadcastType.scale`), which a word must not be.
    static func figure(_ text: String, size: CGFloat) -> Font {
        BroadcastType.isFigure(text) ? numerals(size) : label(size)
    }

    /// The tracking each role carries, so a caller that wants the role's own spacing can ask for
    /// it rather than guessing. Screens that pass their own `kerning` still win. Measured on the
    /// size the face is really drawn at, not the size the caller asked for.
    /// Direction A sets sentence case with the faces' own spacing, so the roles carry none.
    enum Tracking {
        static func display(_ size: CGFloat) -> CGFloat { 0 }
        static func button(_ size: CGFloat) -> CGFloat { 0 }
        static func label(_ size: CGFloat) -> CGFloat { 0 }
    }
}

// MARK: - Blueprint type (system 01 of docs/look/fonts-options.html)

/// Three SIL OFL faces, bundled in `Roboteer/Fonts` and registered at launch:
///
/// - display: Saira Stencil One (one weight, upright) for titles, machine names, ROBOTEER, results;
/// - UI: Saira Semi Condensed, 700 for labels and buttons, 500 for body;
/// - numbers: Saira Semi Condensed 700 with tabular figures (OpenType `tnum`) for scrap, weights,
///   stats, percentages and clocks (wave D, docs/wave-d-figures-notes.md; B612 Mono before, whose
///   fixed pitch opened a gap after ".", ":" and ",": "89. 5 kg").
///
/// Every call site still asks for the size the old Barlow Condensed set wanted. The new faces are
/// wider, so each role draws at a fixed fraction of that (`scale`), and never under its floor.
///
/// The faces are looked up by their PostScript names. If they are not in the build every role
/// falls back to the system face at the same weight, which keeps every screen legible and the
/// layout the same shape. `BroadcastType.usingBundledFamily` says which of the two you are looking
/// at, and the launch log prints it so a screenshot is never ambiguous.
enum BroadcastType {

    /// True when `text` reads as a figure rather than a word: it has a digit and no more than
    /// three letters. `Stage.figure` picks the face with it.
    static func isFigure(_ text: String) -> Bool {
        text.contains(where: \.isNumber) && text.filter(\.isLetter).count <= 3
    }

    /// The legibility floors from spec section 7.
    static let labelFloor: CGFloat = 11
    static let bodyFloor: CGFloat = 13

    /// The size multipliers from the type review (system 01): the stencil is a third wider than
    /// Barlow Condensed, the Saira UI face about a fifth. Figures draw at `figureGrowth` times the
    /// 0.8 the B612 Mono had, so they stand exactly as tall as it did (Saira's figures are 0.696 em,
    /// B612's 0.758) and every readout keeps its weight; a tabular figure is 0.553 em against the
    /// mono's 0.65, so no string grows wider.
    static func scale(_ role: Role) -> CGFloat {
        switch role {
        case .display: return 0.8
        case .label, .body: return 0.94
        case .numerals: return 0.8 * figureGrowth
        }
    }

    /// Saira's figures at this many times a size stand as tall as B612 Mono's at the size (0.758 /
    /// 0.696). `exact(.numerals, size:)` applies it too, so the direction A mockup's mono sizes keep
    /// their height.
    static let figureGrowth: CGFloat = 1.09

    /// The point size a role is really drawn at when a caller asks for `size`. The multiplier never
    /// takes a line under its floor (label 11, everything else 13); a caller that asked for less
    /// than the floor on purpose gets what it asked for.
    static func drawnSize(_ role: Role, size: CGFloat) -> CGFloat {
        let floor: CGFloat = role == .label ? labelFloor : bodyFloor
        return max(size * scale(role), min(size, floor))
    }

    /// The smallest `minimumScaleFactor` a text in this role at this size may carry without
    /// rendering under its floor (bug 12 of docs/aaa/frontend-meta.md: the floors were clamped at
    /// the font and then shrunk straight back under them by the scale factor). Body text at 13 and
    /// labels at 11 get 1, which means they never shrink: a long line wraps or its layout makes
    /// room. Display type has no floor of its own in the spec; small display lines (a 13 pt
    /// banner) take the body floor, so no words on screen are drawn under 13 pt unless they are
    /// capitals in the label role.
    static func floorScale(_ role: Role, size: CGFloat) -> CGFloat {
        let floor: CGFloat
        switch role {
        case .label: floor = labelFloor
        case .body, .display, .numerals: floor = bodyFloor
        }
        let drawn = drawnSize(role, size: size)
        guard drawn > 0 else { return 1 }
        return min(1, floor / drawn)
    }

    /// `minimumScaleFactor` for a caller that wanted `wanted`, raised to the floor if it has to be.
    static func floorScale(_ role: Role, size: CGFloat, wanted: CGFloat) -> CGFloat {
        max(wanted, floorScale(role, size: size))
    }

    enum Role {
        /// Saira Stencil One, display and titles.
        case display
        /// Saira Semi Condensed 700, buttons and labels.
        case label
        /// Saira Semi Condensed 500, body copy.
        case body
        /// Saira Semi Condensed 700 with tabular figures, numbers.
        case numerals
    }

    private static let displayFace = "SairaStencilOne-Regular"
    private static let boldFace = "SairaSemiCondensed-Bold"
    private static let mediumFace = "SairaSemiCondensed-Medium"

    /// Every face the app ships, by PostScript name. Also what `UIAppFonts` lists. The figures are
    /// `boldFace` with the `tnum` feature on (`figureFont`), not a file of their own.
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
        usingBundledFamily = faces.allSatisfy { UIFont(name: $0, size: 12) != nil }
    }

    /// One line for the diagnostics corner: which family the screen you are looking at is set in.
    static var familyNote: String {
        usingBundledFamily
            ? "Blueprint: Saira Stencil One, Saira Semi Condensed (figures tabular)."
            : "System face, the Blueprint faces are not in this build."
    }

    private static var cache: [String: Font] = [:]

    /// The face at exactly `size` points, no role multiplier: direction A's mockup is authored in
    /// the real faces, so its pixel sizes are the sizes. Floors still hold for words.
    static func exact(_ role: Role, size: CGFloat) -> Font {
        let floored: CGFloat
        switch role {
        case .label: floored = max(labelFloor, size)
        case .body: floored = max(bodyFloor, size)
        case .display: floored = max(11, size)
        case .numerals: floored = max(11, size * figureGrowth)
        }
        let key = "exact-\(role)-\(floored)"
        if let hit = cache[key] { return hit }
        let made = make(role, size: floored)
        cache[key] = made
        return made
    }

    /// A figure inside a sentence: the figures face at the words' own size, no `figureGrowth`, so
    /// its capitals match the words' and the line keeps the words' height.
    static func inlineFigures(size: CGFloat) -> Font {
        let floored = max(11, size)
        let key = "inline-\(floored)"
        if let hit = cache[key] { return hit }
        let made = make(.numerals, size: floored)
        cache[key] = made
        return made
    }

    /// The figures face sits in Saira's line box (ascent 1.135 em, descent 0.439), taller than the
    /// B612 Mono one every readout was laid out round (0.965 and 0.25 of the mono's own em, which is
    /// 0.885 and 0.229 of Saira's at `figureGrowth`). `figureLine` pads a figures-only line back to
    /// the mono's box by these fractions of the drawn size; the figures (0.696 em) sit well inside.
    static let figureTrimTop: CGFloat = 0.25
    static let figureTrimBottom: CGFloat = 0.21

    static func font(_ role: Role, size: CGFloat) -> Font {
        let key = "\(role)-\(size)"
        if let hit = cache[key] { return hit }
        let made = make(role, size: drawnSize(role, size: size))
        cache[key] = made
        return made
    }

    private static func make(_ role: Role, size: CGFloat) -> Font {
        switch role {
        case .display:
            if let ui = UIFont(name: displayFace, size: size) { return Font(ui) }
            return .system(size: size, weight: .heavy).width(.expanded)
        case .label:
            if let ui = UIFont(name: boldFace, size: size) { return Font(ui) }
            return .system(size: size, weight: .bold).width(.condensed)
        case .body:
            if let ui = UIFont(name: mediumFace, size: size) { return Font(ui) }
            return .system(size: size, weight: .medium).width(.condensed)
        case .numerals:
            if let ui = figureFont(size: size) { return Font(ui) }
            return .system(size: size, weight: .bold).width(.condensed).monospacedDigit()
        }
    }

    /// The label face with OpenType `tnum` switched on: every figure one width (0.553 em), the
    /// point, colon and comma their own narrow widths.
    static func figureFont(size: CGFloat) -> UIFont? {
        guard let base = UIFont(name: boldFace, size: size) else { return nil }
        let tabular: [[String: Any]] = [[
            kCTFontOpenTypeFeatureTag as String: "tnum",
            kCTFontOpenTypeFeatureValue as String: 1,
        ]]
        let descriptor = base.fontDescriptor.addingAttributes([.featureSettings: tabular])
        return UIFont(descriptor: descriptor, size: size)
    }
}

extension View {
    /// A line that is figures alone (a score, a scrap bug, a readout) keeps the height B612 Mono
    /// gave it: negative padding trims Saira's taller line box (`BroadcastType.figureTrimTop`).
    /// `size` is what the caller passed the font helper; `exact` for `Blueprint.figures(px)`, which
    /// takes no role multiplier.
    func figureLine(_ size: CGFloat, exact: Bool = false) -> some View {
        let drawn = exact
            ? max(11, size * BroadcastType.figureGrowth)
            : BroadcastType.drawnSize(.numerals, size: size)
        return padding(.top, -drawn * BroadcastType.figureTrimTop)
            .padding(.bottom, -drawn * BroadcastType.figureTrimBottom)
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

/// THE plate shape: a plain upright rectangle. **No cut corner, no lean, no rounding** (owner
/// rule, wave E 2026-10-01: the cut corner and the 12 degree lean read as "Claude design"). Every
/// plate, chip, row, badge, lower third and clipped picture in the app is one of these. It was
/// `CutRect` (one chamfered corner) and `LowerThirdShape` (a 12 degree parallelogram); both were
/// deleted rather than left switched off, so no screen can pick a cut or a lean up again.
struct PlateRect: InsettableShape {

    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> PlateRect {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: insetAmount, dy: insetAmount))
    }
}

// There is no bar shape. A lower third used to wear a 3 pt `line` bar on its leading edge; the
// owner ruled those line accents out (2026-09-21), so the shape was deleted rather than left
// about for a screen to pick up again.

// MARK: - Panel (spec section 2)

/// The chrome every panel wears: a blueprint plate (`glass` fill and its grid), upright and
/// square cornered.
///
/// OWNER RULE (2026-09-21): no edge strokes, hairline frames or coloured rules on a panel. The
/// plate is told apart from the stage by its fill and its light, never by a line round it.
struct PanelChrome: View {

    var cut: CGFloat = Stage.corner
    var fill: Color = Stage.glass
    /// A panel over the live arena is lighter, so the machine behind it still reads.
    var overArena: Bool = false
    /// Kept so older call sites compile; the panel draws no rule (owner rule, no line accents).
    var rule: Color = .clear

    var body: some View {
        // Direction A: every panel is a sheet of blueprint paper, the grid its only texture.
        BlueprintPlate(fill: overArena ? Stage.glassOverArena : fill)
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

/// An upright plate (no lean since wave E). Names, card headers, the result banner and every stat
/// strip are one of these. There is no bar on its leading edge and no outline (owner rule, no line accents):
/// `bar` is kept only as the plate's TINT, washed into the fill.
struct LowerThird<Content: View>: View {

    var bar: Color = .clear
    var fill: Color = Stage.glass
    /// Lower thirds enter from the edge they belong to (spec section 3).
    var entersFrom: Edge? = nil
    var padding: EdgeInsets = EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 12)
    /// Extra room on the leading edge. It used to clear the 12 degree lean; the lean is gone and
    /// the inset stays so no copy moves (nothing reflows).
    var leadingInset: CGFloat = 10
    @ViewBuilder var content: Content

    @State private var arrived = false

    var body: some View {
        content
            .padding(padding)
            .padding(.leading, leadingInset)
            .background {
                ZStack {
                    PlateRect().fill(fill)
                    PlateRect().fill(bar.opacity(0.14))
                    PlateRect().fill(Stage.topLight)
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

/// A small upright plate, numerals inside and a label above; a lit one is filled, never rimmed. Scrap, the fight
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
                .minimumScaleFactor(BroadcastType.floorScale(.label, size: 11, wanted: 0.8))
            Text(value)
                .font(Stage.figure(value, size: size))
                .foregroundStyle(dim ? Stage.textFaint : tint)
                .lineLimit(1)
                .minimumScaleFactor(BroadcastType.floorScale(.numerals, size: size, wanted: 0.7))
                .figureLine(BroadcastType.isFigure(value) ? size : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            ZStack {
                PlateRect().fill(lit ? Stage.line.opacity(0.24) : Stage.glass)
                PlateRect().fill(Stage.topLight)
            }
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Rule (spec section 2)

/// A 1 px NEUTRAL divider between sections of one panel, never thicker, never a box, never
/// coloured (owner rule, no line accents: a coloured rule reads as an accent).
struct HairRule: View {
    var tint: Color = Stage.divider
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
        .background { Blueprint.secondary.ignoresSafeArea() }
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

/// A button is a lower third: an upright plate with NO bar, NO outline and NO accent line on any
/// edge (owner rule, 2026-09-21). The primary call to action is a solid bright plate with `ink`
/// type, so it wins by fill and weight alone. Selected or focused, an ordinary button's fill
/// sweeps to `line` from the leading edge in 0.15 s. Pressed, the fill is `line` and the label is
/// `ink`. Primary buttons are 1.5x the height of secondary ones. Danger fills with `danger`.
/// Nothing scales and nothing bounces.
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
        case .primary: return 48
        case .quiet: return 32
        default: return 40
        }
    }

    /// Direction A (docs/look/menus-blueprint.html, states board): the primary is a solid white
    /// plate with blue stencil type; the rest are navy plates with white UI type; danger is a red
    /// plate. Upright, no stroke, no skew. A blocked primary is hatched navy with dim type. Focus
    /// (a pad) lays a white wash over the plate; pressed inverts it.
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && enabled
        return configuration.label
            .font(kind == .primary ? Blueprint.display(24) : Blueprint.ui(kind == .quiet ? 14 : 15))
            .lineLimit(1)
            .minimumScaleFactor(kind == .primary ? 0.6 : BroadcastType.floorScale(.label, size: 15, wanted: 0.75))
            .foregroundStyle(labelTint(pressed: pressed))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .padding(.horizontal, 12)
            .background {
                plate(pressed: pressed)
            }
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: pressed)
            .animation(.easeOut(duration: 0.15), value: focused)
    }

    private func labelTint(pressed: Bool) -> Color {
        if !enabled { return Blueprint.dim }
        switch kind {
        case .primary: return Blueprint.primaryInk
        case .danger: return Color.white
        default: return pressed ? Blueprint.primaryInk : Color.white
        }
    }

    @ViewBuilder
    private func plate(pressed: Bool) -> some View {
        ZStack {
            switch kind {
            case .primary:
                if enabled {
                    Rectangle().fill(pressed ? Color.white.opacity(0.78) : Blueprint.primary)
                    Rectangle().fill(Blueprint.primaryInk.opacity(focused && !pressed ? 0.16 : 0))
                } else {
                    Rectangle().fill(Blueprint.secondary)
                    BlueprintHatch(color: Color.white.opacity(0.28), spacing: 8, width: 2)
                }
            case .danger:
                Rectangle().fill(Blueprint.dangerFill)
                Rectangle().fill(Color.white.opacity(pressed ? 0.3 : (focused ? 0.16 : 0)))
            default:
                Rectangle().fill(pressed ? Blueprint.primary : Blueprint.secondary)
                Rectangle().fill(Blueprint.selected.opacity(focused && !pressed ? 1 : 0))
                if !enabled { BlueprintHatch() }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The name the screens were written against.
typealias StageButtonStyle = BroadcastButtonStyle

/// A broadcast button. Give it a `focusID` and a game pad can land on it: the fill sweep only
/// appears once a pad has been used, so a touch player never sees it. There is no focus ring.
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
        // Direction A's `.lab`: 12 pt UI bold, sentence case, dim.
        Text(text)
            .font(Blueprint.ui(12))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(BroadcastType.floorScale(.label, size: 12, wanted: 0.85))
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
                .minimumScaleFactor(BroadcastType.floorScale(.label, size: 11, wanted: 0.7))
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
        // Direction A's mass gauge: the same drawing everywhere a weight is shown.
        BlueprintMassGauge(used: used, budget: budget)
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
        LowerThird(bar: bar, fill: Stage.type.opacity(0.04), padding: EdgeInsets(top: 3, leading: 4, bottom: 3, trailing: 8), leadingInset: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label.uppercased())
                    .font(Stage.label(11))
                    .kerning(Stage.Tracking.label(11))
                    .foregroundStyle(Stage.textFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(BroadcastType.floorScale(.label, size: 11, wanted: 0.7))
                Spacer(minLength: 4)
                Text(value)
                    .font(Stage.figure(value, size: 15))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .figureLine(BroadcastType.isFigure(value) ? 15 : 0)
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
        PlateRect()
            .fill(Color(hexString: hex))
            .frame(width: size, height: size)
            // Selected is said by size and a lit plate behind, never by a ring.
            .padding(selected ? 3 : 0)
            .background { PlateRect().fill(selected ? Stage.type.opacity(0.85) : Color.clear) }
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
                        .figureLine(13)
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
                    PlateRect().fill(selected ? Stage.selectedFill : Stage.type.opacity(0.03))
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
    /// A segment that answers false is drawn dim with a lock and cannot be chosen (the builder's
    /// armour materials the player does not own, bug 3 of docs/aaa/frontend-meta.md).
    var isEnabled: (Value) -> Bool = { _ in true }
    /// Segments per row. Nil keeps them all on one row. The label floor is 11 pt and a segment
    /// never shrinks its words below it, so a long set wraps onto a second row instead.
    var perRow: Int? = nil

    var body: some View {
        let count = max(1, perRow ?? values.count)
        let rows = stride(from: 0, to: values.count, by: count).map {
            Array(values[$0..<min($0 + count, values.count)])
        }
        VStack(spacing: 2) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 2) {
                    ForEach(rows[index], id: \.self) { value in
                        segment(value)
                    }
                    // A short last row keeps the same segment width as the rows above it.
                    ForEach(0..<(count - rows[index].count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity).frame(height: 1)
                    }
                }
            }
        }
    }

    private func segment(_ value: Value) -> some View {
        let isOn = value == selection
        let enabled = isEnabled(value)
        let fontSize = max(BroadcastType.labelFloor, size)
        return Button {
            selection = value
        } label: {
            // Direction A's tabs: the one on is a white plate with blue type, the rest a faint
            // white wash with dim type. 26 pt tall, 2 pt apart.
            HStack(spacing: 3) {
                if !enabled {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(title(value))
                    .font(Blueprint.ui(fontSize + 0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(BroadcastType.floorScale(.label, size: fontSize))
            }
            .foregroundStyle(isOn ? Blueprint.primaryInk : Blueprint.dim)
            .opacity(enabled ? 1 : 0.45)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background {
                Rectangle().fill(isOn ? Blueprint.primary : Blueprint.tabOff)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityHint(enabled ? "" : "Locked")
    }
}

// MARK: - Hierarchy (spec section 8)

/// The tier strip as ONE LINE OF WORDS, never five boxes (spec section 8).
///
/// The current circuit sits on a filled plate in bright type (no underline: owner rule, no line
/// accents), a locked one is dim behind a lock glyph, and the full game wall is a small dim
/// divider standing between the last free circuit and the first locked one. The screen hands over plain items, so the career is the only place
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
            .fill(Stage.textFaint)
            .frame(width: 1, height: size + 4)
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
                .minimumScaleFactor(BroadcastType.floorScale(.label, size: item.current ? size + 1 : size, wanted: 0.7))
        }
        .padding(.vertical, 2)
        .padding(.horizontal, item.current ? 5 : 0)
        .background {
            PlateRect().fill(item.current ? Stage.selectedFill : Color.clear)
        }
    }
}

/// Navigation that is not the hero (spec section 8): label capitals, no plate, `typeDim` by
/// default, `line` when it leads somewhere important and `danger` when it costs scrap. A pad that
/// lands on it lights a plate behind it, the same fill the tier line uses for "you are here".
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
            // Direction A's quiet links: UI bold, sentence case, a soft shadow to hold over the stage.
            Text(title)
                .font(Blueprint.ui(size + 2))
                .foregroundStyle(focused ? Stage.type : tint)
                .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                .lineLimit(1)
                .fixedSize()
                .padding(.vertical, 5)
                .padding(.horizontal, 4)
                .background {
                    PlateRect().fill(Stage.selectedFill).opacity(focused ? 1 : 0)
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
                .font(Blueprint.inlineFigures(size))
                .foregroundStyle(clause.tint)
            if !clause.tail.isEmpty { out = out + word(clause.tail) }
        }
        return out
    }

    private func word(_ text: String) -> Text {
        Text(text)
            .font(Blueprint.body(size))
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
        // Direction A's `.lab`: "Career. Series 2, match 3", all of it dim, sentence case.
        Text(accent.isEmpty ? label : "\(label.trimmingCharacters(in: CharacterSet(charactersIn: " ·."))). \(accent)")
            .foregroundStyle(Blueprint.dim)
            .font(Blueprint.ui(12))
            .lineLimit(1)
            .minimumScaleFactor(BroadcastType.floorScale(.label, size: 12, wanted: 0.75))
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
        // Direction A: a small navy "Back" plate, top left.
        Button(action: action) {
            Text("Back")
                .font(Blueprint.ui(14))
                .foregroundStyle(Color.white)
                .frame(width: 64, height: 32)
                .background(Blueprint.secondary, ignoresSafeAreaEdges: [])
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
        // The key art ships as JPEG (wave C size pass, docs/wave-c-size-notes.md: every file in
        // Art/ui is an opaque render, so a q92 4:4:4 JPEG is visually lossless at a seventh of
        // the PNG). PNG is still read, for any art that lands later with an alpha channel.
        search: for directory in ["ui", nil] as [String?] {
            for ext in ["jpg", "png"] {
                if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: directory),
                   let image = UIImage(contentsOfFile: url.path) {
                    found = image
                    break search
                }
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
    private var percent: Int { Int((value * 100).rounded()) }

    var body: some View {
        // Direction A's `.cr`: the name, a 56 pt bar (a 4 pt track, a 6 pt fill), the percentage.
        // Danger below a quarter, name, bar and number together.
        let bad = value < 0.25
        HStack(spacing: 8) {
            Text(label)
                .font(Blueprint.ui(13))
                .foregroundStyle(bad ? Blueprint.danger : Color.white)
                .lineLimit(2)
                .minimumScaleFactor(BroadcastType.floorScale(.label, size: 13, wanted: 0.85))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            BlueprintConditionBar(value: value, bad: bad)
                .frame(width: max(40, barWidth + 4), height: 8)
            Text("\(percent)%")
                .font(Blueprint.figures(12.5))
                
                .foregroundStyle(bad ? Blueprint.danger : Color.white)
                .frame(width: 38, alignment: .trailing)
        }
        .frame(minHeight: 25)
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
        // Direction A's payout row (`.pr`): the words in UI type, the number in the figures face.
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(Blueprint.ui(14))
                .foregroundStyle(amount == 0 ? Blueprint.dim : Color.white)
                .lineLimit(1)
                .minimumScaleFactor(BroadcastType.floorScale(.label, size: 14, wanted: 0.75))
            Spacer(minLength: 6)
            if counts && amount != 0 {
                CountingNumber(value: amount, font: Blueprint.figures(size), tint: colour)
                    .figureLine(size, exact: true)
            } else {
                Text("\(amount)")
                    .font(Blueprint.figures(size))
                    .foregroundStyle(colour)
                    .figureLine(size, exact: true)
            }
        }
        .frame(minHeight: 24)
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
/// fill behind it that carries the state (no bar down the edge: owner rule, no line accents). Never a box (design system section 8),
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

    // Direction A's schedule cells (`.m`): a faint white wash; the match on duty is the white
    // plate with blue type; a locked cell is hatched.
    private var headTint: Color {
        switch state {
        case .won, .replay: return Color.white
        case .next: return Blueprint.primaryInk
        case .waiting: return Blueprint.dim
        case .locked: return Stage.textFaint
        }
    }

    private var noteTint: Color { state == .next ? Blueprint.primaryInk.opacity(0.8) : Blueprint.dim }

    private var cellFill: Color {
        switch state {
        case .next: return Blueprint.primary
        case .won, .replay: return Color.white.opacity(0.07)
        case .waiting, .locked: return Color.white.opacity(0.03)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // The label floor holds (bug 12), so a long name takes tighter tracking rather than a
            // smaller size, and is cut short only if it still does not fit.
            Text(head)
                .font(Blueprint.ui(13))
                .allowsTightening(true)
                .foregroundStyle(headTint)
                .lineLimit(1)
                .minimumScaleFactor(BroadcastType.floorScale(.label, size: 11, wanted: 0.6))
            if !note.isEmpty {
                Text(note)
                    .font(Blueprint.ui(11))
                    .foregroundStyle(noteTint)
                    .lineLimit(1)
                    .minimumScaleFactor(BroadcastType.floorScale(.label, size: 11, wanted: 0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background {
            ZStack {
                Rectangle().fill(cellFill)
                if state == .locked { BlueprintHatch() }
            }
        }
        .opacity(state == .locked ? 0.7 : 1)
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

/// A rival's or a boss's portrait: a plate of art, square cornered, no panel round it.
/// Art supports the hero, it does not add a panel (spec section 8), so this is a picture and
/// nothing else: no hairline round it. A portrait nobody has drawn leaves the livery swatch alone.
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
                .clipShape(PlateRect())
                .accessibilityHidden(true)
        }
    }
}

/// An arena card: the 16:9 key art for one arena, square cornered, with the arena's name over the
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
    /// A card in a picker: the unchosen ones sit back (dimmer), the chosen one is lit.
    var inPicker: Bool = false
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
                    .minimumScaleFactor(BroadcastType.floorScale(.display, size: 15, wanted: 0.6))
                if !note.isEmpty {
                    Text(note)
                        .font(Stage.label(11))
                        .kerning(Stage.Tracking.label(11))
                        .foregroundStyle(locked ? Stage.line : Stage.textFaint)
                        .lineLimit(1)
                        .minimumScaleFactor(BroadcastType.floorScale(.label, size: 11, wanted: 0.6))
                }
            }
            .padding(.horizontal, 7)
            .padding(.bottom, 5)
        }
        .frame(width: width, height: height)
        .clipShape(PlateRect())
        // Only the chosen one is lit, so a grid of six reads as one choice rather than six
        // half-made ones: the others are dimmed, never framed (owner rule, no line accents).
        .overlay {
            // The chosen card carries a wash of `line` over its foot, a fill and not a frame.
            LinearGradient(colors: [Stage.line.opacity(0), Stage.line.opacity(0.35)],
                           startPoint: .center, endPoint: .bottom)
                .clipShape(PlateRect())
                .opacity(inPicker && (selected || focused) ? 1 : 0)
                .allowsHitTesting(false)
        }
        .saturation(locked ? 0.2 : ((!inPicker || selected || focused) ? 1 : 0.7))
        .brightness((!inPicker || selected || focused) ? 0 : -0.14)
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
                        .minimumScaleFactor(BroadcastType.floorScale(.display, size: 17, wanted: 0.7))
                    Text(line)
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.typeDim)
                        .lineLimit(1)
                        .minimumScaleFactor(BroadcastType.floorScale(.body, size: 13, wanted: 0.7))
                }
                Spacer(minLength: 4)
                if let portrait {
                    Image(uiImage: portrait)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: height - 10, height: height - 10)
                        .clipShape(PlateRect())
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, 9)
            .padding(.trailing, 5)
        }
        .frame(height: height)
        .clipShape(PlateRect())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name). \(line)")
    }
}

// MARK: - Blueprint: direction A (wave C, owner 2026-09-28)

/// Direction A, "Blueprint overlay" (docs/look/menus-blueprint.html, its CSS is the spec): the live
/// stage stays the hero; every panel is a blueprint plate in the icon's own blue, and leader lines
/// tie the numbers to the real machine. Plates carry no stroke (design system section 0): the grid
/// is their texture, the rules inside tables and the leader lines are diagram content.
enum Blueprint {

    // Plates are square, upright sheets: `PlateRect` is the only plate shape (the old
    // `cutsCorners` and `skews` switches were deleted with the shapes they switched).

    /// `--plate`, rgba(14, 58, 140, 0.9).
    static let plate = Color(hex: 0x0E3A8C).opacity(0.9)
    /// The icon's blue, solid.
    static let blue = Color(hex: 0x0E3A8C)
    /// The 10 pt grid.
    static let gridMinor = Color.white.opacity(0.06)
    /// The 50 pt grid.
    static let gridMajor = Color.white.opacity(0.12)
    /// `--dim`.
    static let dim = Color.white.opacity(0.66)
    /// `--pbg` and `--pfg`: the primary plate and the type on it.
    static let primary = Color.white
    static let primaryInk = Color(hex: 0x0E3A8C)
    /// `--sbg`: the navy of the secondary plate.
    static let secondary = Color(.sRGB, red: 9 / 255, green: 38 / 255, blue: 98 / 255, opacity: 0.94)
    /// `--selbg`: a selected row.
    static let selected = Color.white.opacity(0.2)
    /// `--danger`, readable on the blue, and `--dangerbg`, the danger plate.
    static let danger = Color(hex: 0xFF7A66)
    static let dangerFill = Color(hex: 0xB8352A)
    /// `--tagbg`: a leader's tag.
    static let tag = Color(hex: 0x0E3A8C)
    /// `--rule` (a table's header rule, a title block's cell rule) and `--rule2` (between rows).
    static let rule = Color.white.opacity(0.4)
    static let rule2 = Color.white.opacity(0.13)
    /// `--hatch`: locked things.
    static let hatch = Color.white.opacity(0.16)
    /// A tab that is not on.
    static let tabOff = Color.white.opacity(0.07)

    /// Saira Stencil One at exactly `px`.
    static func display(_ px: CGFloat) -> Font { BroadcastType.exact(.display, size: px) }
    /// Saira Semi Condensed Bold at exactly `px` (the mockup's 600 and 700 both).
    static func ui(_ px: CGFloat) -> Font { BroadcastType.exact(.label, size: px) }
    /// Saira Semi Condensed Medium, body copy.
    static func body(_ px: CGFloat) -> Font { BroadcastType.exact(.body, size: px) }
    /// Figures: Saira Semi Condensed Bold with tabular figures, as tall as the mockup's mono at `px`.
    static func figures(_ px: CGFloat) -> Font { BroadcastType.exact(.numerals, size: px) }
    /// A figure inside a sentence set at `px`: the words' own size, so the line keeps its height.
    static func inlineFigures(_ px: CGFloat) -> Font { BroadcastType.inlineFigures(size: px) }
}

/// The graph paper: a 1 pt line every 10 pt and a brighter one every 50 pt, counted from the
/// plate's own top left. The first line sits one step IN from the top and left edges, never on
/// them (wave E): a bright line along two edges read as a frame round the sheet, which the owner
/// rule forbids. The Godot plate (`Broadcast.draw_grid`) does the same.
struct BlueprintGrid: View {
    var minor: Color = Blueprint.gridMinor
    var major: Color = Blueprint.gridMajor

    var body: some View {
        Canvas { context, size in
            var small = Path()
            var large = Path()
            var step = 1
            var x: CGFloat = 10
            while x < size.width - 1 {
                small.addRect(CGRect(x: x, y: 0, width: 1, height: size.height))
                if step % 5 == 0 { large.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)) }
                x += 10
                step += 1
            }
            step = 1
            var y: CGFloat = 10
            while y < size.height - 1 {
                small.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
                if step % 5 == 0 { large.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)) }
                y += 10
                step += 1
            }
            context.fill(small, with: .color(minor))
            context.fill(large, with: .color(major))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A blueprint plate: the blue, the grid, no stroke, no light.
struct BlueprintPlate: View {
    var fill: Color = Blueprint.plate
    var grid: Bool = true

    var body: some View {
        ZStack {
            Rectangle().fill(fill)
            if grid { BlueprintGrid().clipped() }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Put this content on a blueprint plate.
    func blueprintPlate(_ fill: Color = Blueprint.plate, grid: Bool = true) -> some View {
        background { BlueprintPlate(fill: fill, grid: grid) }
    }
}

/// The hatch on locked things: 1 pt diagonal lines, 7 pt apart, rising left to right.
struct BlueprintHatch: View {
    var color: Color = Blueprint.hatch
    var spacing: CGFloat = 7
    var width: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let step = spacing * 1.4142
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            context.stroke(path, with: .color(color), lineWidth: width)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The condition bar of the match result: a 4 pt track with a 6 pt fill over it.
struct BlueprintConditionBar: View {
    var value: Double
    var bad: Bool = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.18))
                    .frame(height: 4)
                Rectangle().fill(bad ? Blueprint.danger : Color.white)
                    .frame(width: proxy.size.width * min(1, max(0, value)), height: 6)
            }
            .frame(maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }
}

/// The mass gauge: "Mass 87.5 of 100 kg ... 12.5 kg spare" over a dimension line with arrows at
/// both ends, end ticks, a tick every tenth, the used mass as a filled bar and, when a part is
/// being weighed up, what it would add as a paler bar. Over the budget the bar and the words go to
/// danger and the right hand words say by how much.
struct BlueprintMassGauge: View {
    var used: Double
    var budget: Double = BuildRules.budget
    /// Kilograms a pick would add (negative takes weight off). Zero draws nothing extra.
    var adding: Double = 0

    private var over: Bool { used > budget + 0.0001 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Mass").font(Blueprint.ui(12)).foregroundStyle(Blueprint.dim)
                Text(BuildRules.number(used))
                    .font(Blueprint.figures(16))
                    .foregroundStyle(over ? Blueprint.danger : Color.white)
                    .figureLine(16, exact: true)
                Text("of \(BuildRules.number(budget)) kg").font(Blueprint.ui(12)).foregroundStyle(Blueprint.dim)
                Spacer(minLength: 6)
                Text(over ? "Over by \(BuildRules.kilograms(used - budget))" : "\(BuildRules.kilograms(budget - used)) spare")
                    .font(Blueprint.figures(12))
                    .foregroundStyle(over ? Blueprint.danger : Blueprint.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Canvas { context, size in
                let w = size.width
                let fraction = budget > 0 ? min(1, used / budget) : 0
                let tickColor = GraphicsContext.Shading.color(Color.white.opacity(0.7))
                // End ticks, the dimension line and its arrows.
                var ticks = Path()
                ticks.move(to: CGPoint(x: 0.5, y: 4)); ticks.addLine(to: CGPoint(x: 0.5, y: 18))
                ticks.move(to: CGPoint(x: w - 0.5, y: 4)); ticks.addLine(to: CGPoint(x: w - 0.5, y: 18))
                for i in 1..<10 {
                    let x = (w * CGFloat(i) / 10).rounded() + 0.5
                    ticks.move(to: CGPoint(x: x, y: 14)); ticks.addLine(to: CGPoint(x: x, y: 18))
                }
                context.stroke(ticks, with: tickColor, lineWidth: 1)
                var dim = Path()
                dim.move(to: CGPoint(x: 0, y: 11)); dim.addLine(to: CGPoint(x: w, y: 11))
                context.stroke(dim, with: .color(Color.white.opacity(0.55)), lineWidth: 1)
                var arrows = Path()
                arrows.move(to: CGPoint(x: 0, y: 11)); arrows.addLine(to: CGPoint(x: 9, y: 8)); arrows.addLine(to: CGPoint(x: 9, y: 14)); arrows.closeSubpath()
                arrows.move(to: CGPoint(x: w, y: 11)); arrows.addLine(to: CGPoint(x: w - 9, y: 8)); arrows.addLine(to: CGPoint(x: w - 9, y: 14)); arrows.closeSubpath()
                context.fill(arrows, with: .color(Color(hex: 0xE9EFF6)))
                // The mass, and what a pick would add.
                context.fill(Path(CGRect(x: 0, y: 8, width: w * fraction, height: 6)),
                             with: .color(over ? Blueprint.danger : Color.white))
                if adding > 0.0001, budget > 0 {
                    let start = w * fraction
                    let extra = min(w - start, w * adding / budget)
                    if extra > 0 {
                        context.fill(Path(CGRect(x: start, y: 8, width: extra, height: 6)),
                                     with: .color(Color.white.opacity(0.45)))
                    }
                }
            }
            .frame(height: 18)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mass \(BuildRules.number(used)) of \(BuildRules.number(budget)) kilograms")
    }
}

/// One numbered menu row (`.mrow`): the number in the figures face, the name, a chevron. 36 pt tall; a pad
/// that lands on it lays the selected wash behind it.
struct BlueprintMenuRow: View {
    let number: Int
    let title: String
    var enabled: Bool = true
    var focusID: String? = nil
    var height: CGFloat = 36
    var action: () -> Void

    private var focused: Bool {
        guard let focusID else { return false }
        return PadFocus.shared.isFocused(focusID)
    }

    var body: some View {
        Button(action: { if enabled { action() } }) {
            HStack(spacing: 12) {
                Text(String(format: "%02d", number))
                    .font(Blueprint.figures(12))
                    .foregroundStyle(focused ? Color.white : Blueprint.dim)
                    .frame(width: 22, alignment: .leading)
                Text(title)
                    .font(Blueprint.ui(18))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                Text("\u{203A}")
                    .font(Blueprint.body(24))
                    .foregroundStyle(focused ? Color.white : Blueprint.dim)
            }
            .padding(.horizontal, 14)
            .frame(height: height)
            .background { Rectangle().fill(focused ? Blueprint.selected : Color.clear) }
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(.easeOut(duration: 0.15), value: focused)
        .accessibilityLabel(title)
    }
}

/// A 1 pt rule between the rows of one plate: `--rule2` by default, `--rule` under a header.
struct BlueprintRule: View {
    var strong: Bool = false
    var vertical: Bool = false
    var body: some View {
        Rectangle()
            .fill(strong ? Blueprint.rule : Blueprint.rule2)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
            .allowsHitTesting(false)
    }
}

/// A part row (`.prow`): the glyph, the name, a note, and the trailing figure (kilograms in the
/// builder, the price in the shop). 38 pt tall.
struct BlueprintPartRow<Trailing: View>: View {

    enum State {
        case normal
        /// The one being looked at: the white wash.
        case selected
        /// On the machine now: the note in bold white.
        case fitted
        /// Behind a Level or the full game: hatched, name and glyph dim.
        case locked
        /// Cannot be afforded or does not fit: name and glyph a little dim.
        case poor
        /// Already the player's: the note plain white.
        case owned
    }

    let glyph: GlyphArt?
    let name: String
    var note: String = ""
    var noteTint: Color? = nil
    var state: State = .normal
    var focusID: String? = nil
    @ViewBuilder var trailing: Trailing
    var action: () -> Void

    private var focused: Bool {
        guard let focusID else { return false }
        return PadFocus.shared.isFocused(focusID)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                GlyphMark(art: glyph, size: 26, tint: Color.white)
                    .frame(width: 44, height: 26)
                    .opacity(state == .locked ? 0.5 : (state == .poor ? 0.7 : 1))
                Text(name)
                    .font(Blueprint.ui(16))
                    .foregroundStyle(Color.white)
                    .opacity(state == .locked ? 0.5 : (state == .poor ? 0.7 : 1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !note.isEmpty {
                    Text(note)
                        .font(state == .fitted ? Blueprint.ui(13) : Blueprint.body(13))
                        .foregroundStyle(noteTint ?? ((state == .fitted || state == .owned || state == .selected) ? Color.white : Blueprint.dim))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .layoutPriority(1)
                }
                trailing
                    .opacity(state == .locked ? 0.5 : 1)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .background {
                ZStack {
                    Rectangle().fill(state == .selected || focused ? Blueprint.selected : Color.clear)
                    if state == .locked { BlueprintHatch() }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(state == .selected ? .isSelected : [])
    }
}

/// The title block (`.tblock`): a plate of cells, a label over a figure, a 1 pt rule between
/// the cells (a drawing's title block, which is table content, not an accent).
struct BlueprintTitleBlock: View {
    struct Cell: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }
    let cells: [Cell]
    var cellWidth: CGFloat = 90
    var height: CGFloat = 52

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                if index > 0 { BlueprintRule(strong: true, vertical: true) }
                VStack(alignment: .leading, spacing: 5) {
                    Text(cell.label).font(Blueprint.ui(12)).foregroundStyle(Blueprint.dim)
                    Text(cell.value)
                        .font(Stage.figure(cell.value, size: 17.5))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .figureLine(BroadcastType.isFigure(cell.value) ? 17.5 : 0)
                }
                .padding(.horizontal, 10)
                .frame(width: cellWidth - (index > 0 ? 1 : 0), height: height, alignment: .leading)
            }
        }
        .blueprintPlate()
        .accessibilityElement(children: .combine)
    }
}

/// The scrap block, top right: "Scrap" over the figure, on a plate, right aligned.
struct BlueprintScrapBlock: View {
    let amount: Int
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Scrap").font(Blueprint.ui(12)).foregroundStyle(Blueprint.dim)
            CountingNumber(value: amount, font: Blueprint.figures(19), tint: Color.white, animated: false)
        }
        .padding(.horizontal, 12)
        .frame(width: 104, height: 40, alignment: .trailing)
        .blueprintPlate()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(amount) scrap")
    }
}

/// One payout row (`.pr`), and the banked total under a rule.
struct BlueprintPayoutRow: View {
    let label: String
    let amount: Int
    var total: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if total { BlueprintRule(strong: true).padding(.top, 6).padding(.bottom, 6) }
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(Blueprint.ui(14)).foregroundStyle(Color.white)
                Spacer(minLength: 6)
                CountingNumber(value: amount, font: Blueprint.figures(total ? 30 : 14), tint: Color.white,
                               animated: total)
                    .figureLine(total ? 30 : 14, exact: true)
            }
            .frame(minHeight: total ? 0 : 24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(amount)")
    }
}

/// A leader's tag (`.tag`): the part's name, a mono figure in the dim, and an optional second
/// line; a damaged part's figure in danger.
struct LeaderTag: View {
    let title: String
    var value: String = ""
    var sub: String = ""
    var danger: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(Blueprint.ui(13)).foregroundStyle(Color.white)
                if !value.isEmpty {
                    Text(value)
                        .font(Blueprint.figures(12))
                        .foregroundStyle(danger ? Blueprint.danger : Blueprint.dim)
                }
            }
            if !sub.isEmpty {
                Text(sub).font(Blueprint.body(12)).foregroundStyle(Blueprint.dim)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 9)
        .padding(.top, 5)
        .padding(.bottom, 6)
        .background(Blueprint.tag, ignoresSafeAreaEdges: [])
        .accessibilityElement(children: .combine)
    }
}

/// The wordmark's emblem: the app icon's crossed axes and gear, white line on the icon blue
/// (emblem 9 version C, the owner's pick), drawn from the icon's own geometry.
struct RoboteerEmblem: View {
    var size: CGFloat = 36

    var body: some View {
        Canvas { context, canvas in
            let scale = canvas.width / 1024
            context.scaleBy(x: scale, y: scale)
            let stroke = StrokeStyle(lineWidth: 40, lineJoin: .round)
            let white = GraphicsContext.Shading.color(.white)
            let blue = GraphicsContext.Shading.color(Blueprint.blue)

            func axe(_ mirror: CGFloat) -> [Path] {
                var shaft = Path(roundedRect: CGRect(x: -24, y: -400, width: 48, height: 800), cornerRadius: 24)
                shaft = shaft.applying(.identity)
                let knob = Path(ellipseIn: CGRect(x: -38, y: 348, width: 76, height: 76))
                var blade = Path()
                blade.move(to: CGPoint(x: -24 * mirror, y: -364))
                blade.addLine(to: CGPoint(x: -200.4 * mirror, y: -434))
                blade.addQuadCurve(to: CGPoint(x: -183.6 * mirror, y: -100), control: CGPoint(x: -262.6 * mirror, y: -270))
                blade.addQuadCurve(to: CGPoint(x: -24 * mirror, y: -204), control: CGPoint(x: -82.8 * mirror, y: -214))
                blade.closeSubpath()
                var spike = Path()
                spike.move(to: CGPoint(x: 24 * mirror, y: -330))
                spike.addLine(to: CGPoint(x: 120 * mirror, y: -288))
                spike.addLine(to: CGPoint(x: 24 * mirror, y: -250))
                spike.closeSubpath()
                return [shaft, knob, blade, spike]
            }

            for (angle, mirror) in [(-40.0, 1.0), (40.0, -1.0)] {
                let transform = CGAffineTransform(translationX: 512, y: 530).rotated(by: angle * .pi / 180)
                let pieces = axe(CGFloat(mirror)).map { $0.applying(transform) }
                for piece in pieces { context.stroke(piece, with: white, style: stroke) }
                for piece in pieces { context.fill(piece, with: blue) }
            }
            let centre = CGAffineTransform(translationX: 512, y: 530)
            var teeth: [Path] = []
            for tri in [[(-73.8, -109.4), (28.1, -267.5), (40.8, -125.5)],
                        [(131.7, -9.2), (217.6, 158.1), (88.3, 98.1)],
                        [(-57.9, 118.6), (-245.7, 109.4), (-129.1, 27.4)]] {
                var path = Path()
                path.move(to: CGPoint(x: tri[0].0, y: tri[0].1))
                path.addLine(to: CGPoint(x: tri[1].0, y: tri[1].1))
                path.addLine(to: CGPoint(x: tri[2].0, y: tri[2].1))
                path.closeSubpath()
                teeth.append(path.applying(centre))
            }
            for tooth in teeth { context.stroke(tooth, with: white, style: stroke) }
            for tooth in teeth { context.fill(tooth, with: blue) }
            var ring = Path(ellipseIn: CGRect(x: -165, y: -165, width: 330, height: 330))
            ring.addPath(Path(ellipseIn: CGRect(x: -44.6, y: -44.6, width: 89.2, height: 89.2)))
            ring = ring.applying(centre)
            context.stroke(ring, with: white, style: stroke)
            context.fill(ring, with: blue, style: FillStyle(eoFill: true))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "Roboteer" with the emblem: the main menu's wordmark.
struct BlueprintWordmark: View {
    var size: CGFloat = 30
    var body: some View {
        HStack(spacing: 10) {
            RoboteerEmblem(size: size * 1.2)
            Text("Roboteer")
                .font(Blueprint.display(size))
                .foregroundStyle(Color.white)
        }
        .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Roboteer")
    }
}
