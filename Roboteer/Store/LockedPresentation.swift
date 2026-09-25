//
//  LockedPresentation.swift
//  How a locked thing looks anywhere in the game: a small lock badge with the sentence from
//  `Gates.lockedReason`, and a row modifier that greys the row and stops it being chosen.
//
//  The rule the whole app follows: a locked thing is always visible and always readable. It is
//  never hidden, never blurred and never replaced with a buy button. The player can see the rest
//  of the game and can see exactly what opens it, which is the only honest version of a wall.
//

import SwiftUI

// MARK: - The badge

/// A lock and a short sentence, on glass. Sits in the corner of a locked row or panel.
struct LockedBadge: View {
    let reason: String
    var compact: Bool = false

    init(_ reason: String, compact: Bool = false) {
        self.reason = reason
        self.compact = compact
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .bold))
            Text(reason.uppercased())
                .font(Stage.label(11, weight: .bold))
                .kerning(0.6)
                .lineLimit(2)
                .minimumScaleFactor(BroadcastType.floorScale(.label, size: 11, wanted: 0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Stage.text)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(Stage.glassDeep, in: CutRect(6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Locked. \(reason)")
    }
}

// MARK: - The row modifier

/// Greys a row out, takes its taps away, and puts the reason on it. A nil reason draws the row
/// exactly as it was, so a caller can write `.lockedRow(gates.lockedReasonIfLocked(.part(id)))`
/// and never branch.
struct LockedRow: ViewModifier {
    let reason: String?
    var alignment: Alignment = .topTrailing
    var compact: Bool = true

    func body(content: Content) -> some View {
        content
            .opacity(reason == nil ? 1 : 0.34)
            .allowsHitTesting(reason == nil)
            .overlay(alignment: alignment) {
                if let reason {
                    LockedBadge(reason, compact: compact)
                        .padding(6)
                }
            }
            .accessibilityHint(reason ?? "")
    }
}

extension View {

    /// The one way a screen says "this is behind the wall".
    func lockedRow(_ reason: String?, alignment: Alignment = .topTrailing, compact: Bool = true) -> some View {
        modifier(LockedRow(reason: reason, alignment: alignment, compact: compact))
    }

    /// The same thing asked as a question, for callers that hold the gates and the subject.
    func lockedRow(_ gates: Gates, _ locked: Gates.Locked, alignment: Alignment = .topTrailing) -> some View {
        modifier(LockedRow(reason: gates.lockedReasonIfLocked(locked), alignment: alignment, compact: true))
    }
}

// MARK: - A locked whole panel

/// For a screen sized thing that is entirely behind the wall (the events list, the replay list,
/// the ladder): the content greyed out with one badge and one line under it.
struct LockedPanel<Content: View>: View {
    let reason: String?
    @ViewBuilder var content: Content

    var body: some View {
        // Bug 13 (docs/aaa/frontend-meta.md): the badge used to be laid across the middle of the
        // content, over the Replays empty-state sentence and across the Events panels, so neither
        // could be read. It now stands above the greyed content, in the flow, and covers nothing.
        if let reason {
            VStack(alignment: .leading, spacing: 10) {
                LockedBadge(reason, compact: false)
                content
                    .opacity(0.34)
                    .allowsHitTesting(false)
                    .accessibilityHint(reason)
            }
        } else {
            content
        }
    }
}
