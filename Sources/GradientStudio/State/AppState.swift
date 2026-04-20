import Foundation
import Observation
import CoreGraphics

/// Preview pane aspect-ratio lock. `.free` lets the preview fill whatever space is
/// available; the other cases letterbox the Metal view to match an export shape.
enum PreviewAspect: String, CaseIterable, Identifiable {
    case free
    case square          // 1:1
    case landscape       // 16:9
    case portrait        // 9:16 ("Vertical")

    var id: String { rawValue }
    var label: String {
        switch self {
        case .free:      return "Fit"
        case .square:    return "1:1"
        case .landscape: return "16:9"
        case .portrait:  return "Vertical"
        }
    }

    /// nil ⇒ no constraint (fill parent). Otherwise width-over-height.
    var ratio: CGFloat? {
        switch self {
        case .free:      return nil
        case .square:    return 1
        case .landscape: return 16.0 / 9.0
        case .portrait:  return 9.0 / 16.0
        }
    }
}

@Observable
final class AppState {
    var params: RenderParams = .default
    var isAnimating: Bool = true
    /// Seconds of animation time consumed so far. Advanced by the preview delegate
    /// on each frame while `isAnimating` is true.
    @ObservationIgnored var time: Float = 0

    /// Last successful export URL (used for the toast/open-in-Finder action).
    var lastExportURL: URL? = nil

    /// View-only preview constraint. Not part of `params`, so toggling it doesn't
    /// register on the undo stack — it's a viewport preference, not gradient data.
    var previewAspect: PreviewAspect = .free

    // MARK: - Undo / Redo

    /// Drives the undo button's disabled state. Kept as a separate bool so toolbar
    /// doesn't re-observe the (heavy) `undoStack` array directly.
    var canUndo: Bool = false
    var canRedo: Bool = false

    @ObservationIgnored private var undoStack: [RenderParams] = []
    @ObservationIgnored private var redoStack: [RenderParams] = []
    @ObservationIgnored private var pendingCheckpoint: DispatchWorkItem?
    @ObservationIgnored private var pendingCandidate: RenderParams?
    @ObservationIgnored private var isPerformingHistoryChange = false
    private let maxHistory = 50
    private let checkpointDebounceSeconds = 0.5

    /// Called from a `.onChange(of: state.params)` with the *old* value. Coalesces
    /// rapid changes (e.g. a slider drag) into a single undo step by debouncing:
    /// only the first `oldValue` in a burst is kept, and the snapshot commits
    /// `checkpointDebounceSeconds` after the last change in the burst.
    func scheduleCheckpoint(oldValue: RenderParams) {
        guard !isPerformingHistoryChange else { return }
        if pendingCandidate == nil {
            pendingCandidate = oldValue
        }
        pendingCheckpoint?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.commitCheckpoint() }
        pendingCheckpoint = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + checkpointDebounceSeconds,
            execute: item
        )
    }

    private func commitCheckpoint() {
        defer {
            pendingCheckpoint = nil
            pendingCandidate = nil
        }
        guard let prior = pendingCandidate, prior != params else { return }
        undoStack.append(prior)
        if undoStack.count > maxHistory {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        refreshFlags()
    }

    func undo() {
        // Flush any pending checkpoint first so an in-flight edit doesn't get lost.
        pendingCheckpoint?.cancel()
        commitCheckpoint()

        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(params)
        performHistoryChange { self.params = snapshot }
        refreshFlags()
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(params)
        performHistoryChange { self.params = snapshot }
        refreshFlags()
    }

    /// Suppresses checkpoint scheduling while `body` runs and for one run-loop tick
    /// after, so the `onChange` ripple from `params = snapshot` doesn't record the
    /// undo/redo itself as a new edit.
    private func performHistoryChange(_ body: () -> Void) {
        isPerformingHistoryChange = true
        body()
        DispatchQueue.main.async { [weak self] in
            self?.isPerformingHistoryChange = false
        }
    }

    private func refreshFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
