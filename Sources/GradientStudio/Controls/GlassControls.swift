import SwiftUI

struct GlassControls: View {
    @Binding var params: RenderParams

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Enabled", isOn: $params.glassEnabled)
            labelled("Aberration",  value: $params.glassAberration,  range: 0...1)
                .disabled(!params.glassEnabled)
            labelled("Blur radius", value: $params.glassBlurRadius, range: 0...0.5)
                .disabled(!params.glassEnabled)
        }
    }
}
