//
//  ReplayPlayerView.swift
//  Watching one replay: the arena re-simulating the fight from the recorded inputs, with the
//  shell's replay bar over it.
//
//  The bar is the whole of the shell's part. Play and pause, 0.25x 0.5x 1x, restart, a scrubber
//  bound to `replay_state`, and Share clip. Everything it does is one `replay_control` message
//  (docs/stage6-spec.md section 2); the arena owns the simulation, the camera and the time scale.
//
//  Sharing is ReplayKit. `RPScreenRecorder.startRecording` records the whole screen, which is the
//  Godot view plus this bar, and `stopRecording` hands back an `RPPreviewViewController`. That
//  preview is the reliable path and the one used here: it is Apple's own trim and share sheet, it
//  needs no photo library permission and no exported file of our own, and it works on a device
//  where writing a movie to a temporary URL and handing it to `UIActivityViewController` can be
//  refused. The recorder is capped at 30 seconds and the microphone is never turned on, so the
//  app needs no `NSMicrophoneUsageDescription` and no `NSPhotoLibraryAddUsageDescription`.
//

import SwiftUI
import SwiftData
import ReplayKit
import UIKit

// MARK: - The player

struct ReplayPlayerView: View {

    @Bindable var host: ArenaHost
    let log: FightLog
    var onBack: () -> Void

    @State private var recorder = ClipRecorder.shared
    @State private var didStart = false
    @State private var scrubbing = false
    @State private var scrubTick: Double = 0

    private var state: ArenaHost.ReplayState? { host.replayState }
    private var total: Double {
        Double(max(1, state?.total ?? ReplayPayload.tickCount(from: log.replayJSON) ?? 1))
    }
    private var tick: Double {
        scrubbing ? scrubTick : Double(state?.tick ?? 0)
    }
    private var canShare: Bool { Gates.current.sharingAvailable }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // The arena is the root Godot view behind this whole stack.
                VStack(spacing: 0) {
                    topRow
                    Spacer(minLength: 0)
                    bar
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
            .onAppear { start(fallbackInsets: proxy.safeAreaInsets) }
        }
        .statusBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onDisappear { recorder.cancel() }
    }

    // MARK: Top row

    private var topRow: some View {
        HStack(alignment: .top, spacing: 10) {
            StageButton("Back", kind: .glass) {
                recorder.cancel()
                onBack()
            }
            .frame(width: 104)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Text("REPLAY")
                    .font(Stage.display(13))
                    .kerning(1.8)
                    .foregroundStyle(Stage.textDim)
                Text("\(log.botName.uppercased()) AGAINST \(log.opponentName.uppercased())")
                    .font(Stage.label(10, weight: .bold))
                    .kerning(0.8)
                    .foregroundStyle(Stage.textFaint)
                if let message = recorder.message {
                    Text(message)
                        .font(Stage.body(10))
                        .foregroundStyle(Stage.textDim)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 280, alignment: .trailing)
                }
            }
        }
    }

    // MARK: The bar

    private var bar: some View {
        GlassPanel(padding: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    StageButton(host.replayIsPlaying ? "Pause" : "Play", kind: .primary) {
                        host.setReplayPlaying(!host.replayIsPlaying)
                    }
                    .frame(width: 112)

                    StageButton("Restart", kind: .glass) {
                        host.restartReplay()
                    }
                    .frame(width: 112)

                    StageSegments(
                        values: ReplaySpeed.allCases,
                        title: { $0.title },
                        selection: Binding(
                            get: { ReplaySpeed.nearest(host.replaySpeed) },
                            set: { host.setReplaySpeed($0.rawValue) }
                        )
                    )
                    .frame(width: 230)

                    Spacer(minLength: 0)

                    Text(timeLine)
                        .font(Stage.numerals(13))
                        .foregroundStyle(Stage.textDim)

                    shareButton
                }

                Slider(
                    value: Binding(
                        get: { tick },
                        set: { scrubTick = $0 }
                    ),
                    in: 0...total,
                    onEditingChanged: { editing in
                        if editing {
                            scrubbing = true
                            scrubTick = Double(state?.tick ?? 0)
                        } else {
                            scrubbing = false
                            // Seeking backwards makes the arena re-simulate from the start, so the
                            // seek goes out once, on release, and never while the thumb moves.
                            host.seekReplay(to: Int(scrubTick.rounded()))
                        }
                    }
                )
                .tint(Stage.text)

                Text("Free camera. Drag to look around, pinch to pull back. It stays where you put it and never eases back.")
                    .font(Stage.body(10))
                    .foregroundStyle(Stage.textFaint)
            }
        }
    }

    private var shareButton: some View {
        Group {
            if recorder.isRecording {
                StageButton("Stop (\(recorder.secondsLeft) s)", kind: .primary) {
                    recorder.stopAndPreview()
                }
                .frame(width: 150)
            } else {
                StageButton("Share clip", enabled: canShare && recorder.isAvailable) {
                    recorder.start()
                }
                .frame(width: 150)
                .lockedRow(Gates.current.lockedReasonIfLocked(.sharing), alignment: .center)
            }
        }
    }

    private var timeLine: String {
        let ticks = Int(tick.rounded())
        let totalTicks = Int(total.rounded())
        // The arena ticks at 60 Hz, which is the contract's physics rate.
        let seconds = Double(ticks) / 60.0
        let totalSeconds = Double(totalTicks) / 60.0
        return String(format: "%.1f / %.1f s", seconds, totalSeconds)
    }

    // MARK: Starting

    private func start(fallbackInsets: EdgeInsets) {
        guard !didStart else { return }
        didStart = true
        PadFocus.shared.clear()
        host.arenaScreenAppeared()
        DispatchQueue.main.async {
            let safeArea = SafeAreaPixels.current(fallback: fallbackInsets)
            guard let json = ReplayPayload.config(from: log, safeArea: safeArea) else {
                host.errorText = "That fight has no recording this build can play."
                return
            }
            host.sentSafeArea = safeArea
            host.startReplay(configJSON: json)
        }
    }
}

// MARK: - Speeds

/// The three speeds the spec allows. Slow motion is `Engine.time_scale` in the arena only: the
/// physics tick rate does not change, so a slowed replay is the same simulation.
enum ReplaySpeed: Double, CaseIterable, Hashable, Identifiable {
    case quarter = 0.25
    case half = 0.5
    case full = 1.0

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .quarter: return "0.25x"
        case .half: return "0.5x"
        case .full: return "1x"
        }
    }

    static func nearest(_ value: Double) -> ReplaySpeed {
        allCases.min(by: { abs($0.rawValue - value) < abs($1.rawValue - value) }) ?? .full
    }
}

// MARK: - The clip

/// ReplayKit, wrapped so the view only has to say start and stop.
///
/// What this does and does not do:
/// - records the whole screen, which is the Godot view plus the replay bar, exactly as the spec asks
/// - never enables the microphone, so no `NSMicrophoneUsageDescription` is needed and nothing the
///   player says is captured
/// - stops itself at 30 seconds, which is the cap in the spec
/// - hands the recording to `RPPreviewViewController`, Apple's own trim and share screen. Nothing
///   is written to the photo library by this app, so no `NSPhotoLibraryAddUsageDescription` either
/// - is unavailable in the Simulator, where `RPScreenRecorder.isAvailable` is false, and says so
@Observable
final class ClipRecorder: NSObject, RPPreviewViewControllerDelegate {

    static let shared = ClipRecorder()

    /// The cap from docs/stage6-spec.md section 2.
    static let maximumSeconds = 30

    private(set) var isRecording = false
    private(set) var secondsLeft = ClipRecorder.maximumSeconds
    /// A plain sentence for the player. Never an error code.
    private(set) var message: String?

    @ObservationIgnored private var countdown: Timer?

    var isAvailable: Bool { RPScreenRecorder.shared().isAvailable }

    private override init() {
        super.init()
    }

    func start() {
        guard !isRecording else { return }
        let recorder = RPScreenRecorder.shared()
        recorder.isMicrophoneEnabled = false
        guard recorder.isAvailable else {
            message = ArenaHost.isSimulator
                ? "Screen recording is not available in the Simulator. This works on a device."
                : "Screen recording is not available right now."
            return
        }
        message = nil
        recorder.startRecording { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.isRecording = false
                    self.stopCountdown()
                    self.message = "The recording did not start. \(error.localizedDescription)"
                    spikeLog.error("ReplayKit startRecording failed: \(String(describing: error), privacy: .public)")
                    return
                }
                self.isRecording = true
                self.secondsLeft = Self.maximumSeconds
                self.message = "Recording. It stops by itself after \(Self.maximumSeconds) seconds."
                self.startCountdown()
            }
        }
    }

    /// Stop and show Apple's preview, which is where the player trims and shares.
    func stopAndPreview() {
        guard isRecording else { return }
        stopCountdown()
        RPScreenRecorder.shared().stopRecording { [weak self] preview, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRecording = false
                if let error {
                    self.message = "The clip could not be finished. \(error.localizedDescription)"
                    spikeLog.error("ReplayKit stopRecording failed: \(String(describing: error), privacy: .public)")
                    return
                }
                guard let preview else {
                    self.message = "The clip came back empty."
                    return
                }
                preview.previewControllerDelegate = self
                preview.modalPresentationStyle = .fullScreen
                guard let host = Self.topViewController() else {
                    self.message = "There was nowhere to show the clip."
                    return
                }
                self.message = nil
                host.present(preview, animated: true)
            }
        }
    }

    /// Leaving the screen, or going back, throws the recording away rather than leaving ReplayKit
    /// running behind the menus.
    func cancel() {
        stopCountdown()
        guard isRecording else { return }
        isRecording = false
        message = nil
        RPScreenRecorder.shared().stopRecording { _, _ in }
    }

    // MARK: Countdown

    private func startCountdown() {
        stopCountdown()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.isRecording else { return }
                self.secondsLeft -= 1
                if self.secondsLeft <= 0 {
                    self.stopAndPreview()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdown = timer
    }

    private func stopCountdown() {
        countdown?.invalidate()
        countdown = nil
        secondsLeft = Self.maximumSeconds
    }

    // MARK: RPPreviewViewControllerDelegate

    func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        previewController.dismiss(animated: true)
    }

    // MARK: Presentation

    /// The view controller to present Apple's preview from. SwiftUI has no controller to hand
    /// over, so the key window's own is asked for.
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = active?.windows.first { $0.isKeyWindow } ?? active?.windows.first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
