import SwiftUI

struct PostControls: View {
    @Binding var params: RenderParams

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            labelled("Grain",    value: $params.grainAmount,    range: 0...0.1)
            labelled("Vignette", value: $params.vignetteAmount, range: 0...1)
        }
    }
}
