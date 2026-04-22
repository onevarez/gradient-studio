import SwiftUI

struct GlassControls: View {
    @Binding var params: GlassParams

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Enabled", isOn: $params.enabled)
            labelled("Aberration",  value: $params.aberration,  range: 0...1)
                .disabled(!params.enabled)
            labelled("Blur radius", value: $params.blurRadius, range: 0...0.5)
                .disabled(!params.enabled)
        }
    }
}
