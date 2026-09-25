//
//  PaintJobs.swift
//  The ten cosmetic paint jobs of brief v5 section 7 (wave P, agent G).
//
//  Paint is free and Level gated: one opens every ten Levels, nothing is bought, and
//  nothing about it touches a fight. The catalogue (`progression.paint_jobs` in
//  `Shared/parts.json`) owns the ids, the names and the Levels; this file owns the art,
//  which is the preview the builder's picker shows, and the question of whether a paint job
//  is finished enough to offer.
//
//  The machine itself is painted in the arena: `BotBuild.paintID` rides to Godot as
//  `bots[i].paint` and `Arena/bot/livery.gd` turns it into a detail overlay on the livery
//  material, so the same paint job works over any of the six livery colours. The previews
//  here are rendered from the SAME textures with the SAME blend arithmetic
//  (`Tools/paint/make_paint.py`), on a deliberately neutral panel, so the picker cannot
//  promise a look the machine does not give. See docs/paint-jobs.md.
//

import SwiftUI

enum PaintJobs {

    // MARK: - The list

    /// Every paint job, in Level order, with `unlocked` false. Use `unlocked(at:)` when the
    /// player's Level is known.
    static var list: [PaintJob] { ProgressionEngine.paintJobs(level: 0) }

    /// Every paint job with `unlocked` filled in for this Level.
    static func unlocked(at level: Int) -> [PaintJob] {
        ProgressionEngine.paintJobs(level: level)
    }

    /// Is this one open at that Level? An id the catalogue does not carry is never open.
    static func unlocked(_ id: String, at level: Int) -> Bool {
        guard let job = entry(id) else { return false }
        return level >= job.level
    }

    /// "Hazard stripe". The id itself when the catalogue has never heard of it, which can
    /// only happen to a save written by a later build of the game.
    static func name(_ id: String) -> String {
        entry(id)?.name ?? id
    }

    /// The Level it opens at, or 0 for an id the catalogue does not carry.
    static func level(_ id: String) -> Int {
        entry(id)?.level ?? 0
    }

    private static func entry(_ id: String) -> PaintJob? {
        list.first { $0.id == id }
    }

    // MARK: - The art

    /// The paint jobs whose art is finished to the bar in docs/graphics-bar.md.
    ///
    /// The picker offers a paint job only when its art ships. One that is listed in the
    /// catalogue but missing from here still appears, still says which Level it opens at,
    /// and simply cannot be chosen: a Level milestone that quietly vanished would be worse
    /// than one that is visibly not ready, and placeholder art is worse than both
    /// (brief v5 section 1).
    static let shipped: Set<String> = [
        "paint_hazard", "paint_racing", "paint_camo", "paint_chequer", "paint_flames",
        "paint_carbon", "paint_chrome", "paint_circuit", "paint_hex", "paint_gold"
    ]

    /// Preview image name in `Art/paint/`, or nil when the id is unknown.
    static func previewName(_ id: String) -> String? {
        guard entry(id) != nil, shipped.contains(id) else { return nil }
        return id
    }

    /// The 512 square preview, or nil when this build has no art for it.
    ///
    /// `Art/paint` ships as a folder reference exactly as `Art/ui` does, so the files land
    /// in the bundle under `paint/`. Every lookup is allowed to fail and nothing on screen
    /// depends on one: the picker draws its own swatch when a preview is missing.
    static func preview(_ id: String) -> UIImage? {
        guard let name = previewName(id) else { return nil }
        if let hit = cache[name] { return hit }
        var found: UIImage?
        for directory in ["paint", nil] as [String?] {
            if let url = Bundle.main.url(forResource: name, withExtension: "png",
                                         subdirectory: directory),
               let image = UIImage(contentsOfFile: url.path) {
                found = image
                break
            }
        }
        cache[name] = found
        return found
    }

    private static var cache: [String: UIImage?] = [:]

    // MARK: - Fitting one

    /// The paint job a machine may actually wear: nil when it has none, when the id is one
    /// this build has no art for, or when the player's Level has not reached it yet. The
    /// builder's livery section checks the fitted paint against this when it opens and takes
    /// off anything that no longer qualifies, so a paint job cannot survive on a save after
    /// the catalogue moves its Level or after the art is pulled from a build.
    static func fitted(_ id: String?, at level: Int) -> String? {
        guard let id, !id.isEmpty, shipped.contains(id), unlocked(id, at: level) else {
            return nil
        }
        return id
    }
}

// MARK: - The picker tile

/// One cell of the builder's paint wall.
///
/// `job` nil is PLAIN, which is always available and is what every machine starts in. A
/// locked paint job is drawn, dimmed, with the Level it arrives at, because the point of a
/// free milestone is being able to see it coming. A paint job whose art this build does not
/// carry cannot be chosen and says so.
struct PaintTile: View {

    /// nil means plain livery, no paint.
    let job: PaintJob?
    let selected: Bool
    /// The player's Level, which is what opens a paint job.
    let level: Int
    let action: () -> Void

    private var locked: Bool {
        guard let job else { return false }
        return level < job.level || !PaintJobs.shipped.contains(job.id)
    }

    private var title: String { job?.name ?? "Plain" }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    if let job, let image = PaintJobs.preview(job.id) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        // Plain livery, and the honest fallback for a preview that did not
                        // load: the panel with nothing on it.
                        LinearGradient(colors: [Stage.type.opacity(0.24), Stage.type.opacity(0.10)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                    if locked, let job {
                        Rectangle().fill(Stage.ink.opacity(0.62))
                        Text("Level \(job.level)".uppercased())
                            .font(Stage.label(11, weight: .bold))
                            .kerning(0.8)
                            .foregroundStyle(Stage.text)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(CutRect(8))
                // The chosen tile sits on a lit plate and wears a tick: a fill, never a ring
                // (owner rule, no line accents).
                .padding(selected ? 3 : 0)
                .background { CutRect(9).fill(selected ? Stage.line : Color.clear) }
                .overlay(alignment: .bottomTrailing) {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(Stage.ink)
                            .frame(width: 18, height: 18)
                            .background(Stage.line, in: CutRect(4))
                    }
                }

                Text(title.uppercased())
                    .font(Stage.label(11, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(selected ? Stage.text : Stage.textDim)
                    .lineLimit(1)
                    .minimumScaleFactor(BroadcastType.floorScale(.label, size: 11, wanted: 0.7))
            }
            .opacity(locked ? 0.42 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!locked)
        .accessibilityLabel(accessibility)
    }

    private var accessibility: String {
        guard let job else { return selected ? "Plain, fitted" : "Plain" }
        if !PaintJobs.shipped.contains(job.id) { return "\(job.name), not in this build" }
        if level < job.level { return "\(job.name), opens at Level \(job.level)" }
        return selected ? "\(job.name), fitted" : job.name
    }
}
