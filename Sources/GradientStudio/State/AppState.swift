import Foundation
import Observation

@Observable
final class AppState {
    var params: RenderParams = .default
    var isAnimating: Bool = true
    /// Seconds of animation time consumed so far. Advanced by the preview delegate
    /// on each frame while `isAnimating` is true.
    @ObservationIgnored var time: Float = 0

    /// Last successful export URL (used for the toast/open-in-Finder action).
    var lastExportURL: URL? = nil
}
