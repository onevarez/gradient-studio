import SwiftUI

struct PostControls: View {
    @Binding var params: RenderParams

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Grain Style", selection: $params.globals.grainStyle) {
                ForEach(GrainStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.segmented)

            labelled("Grain", value: $params.grainAmount, range: 0...1)

            // Cell-size only meaningful in halftone modes; hide it for film
            // so the panel stays focused on what's actually doing work.
            if params.globals.grainStyle != .film {
                labelled("Halftone Scale (px)",
                         value: $params.globals.grainScale,
                         range: 2...40)
            }

            labelled("Vignette", value: $params.vignetteAmount, range: 0...1)
        }
    }
}
