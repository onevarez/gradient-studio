import SwiftUI

struct RadialControls: View {
    @Binding var params: RadialParams

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ColorPicker("Color", selection: colorBinding($params, \.color), supportsOpacity: false)
            labelled("Center X", value: centerX, range: 0...1)
            labelled("Center Y", value: centerY, range: 0...1)
            labelled("Radius", value: $params.radius, range: 0.05...1.5)
            labelled("Falloff", value: $params.falloff, range: 0.5...6)
            labelled("Intensity", value: $params.intensity, range: 0...2)
            labelled("Drift speed (rad/s)", value: $params.driftSpeed, range: -1...1)
            labelled("Drift radius", value: $params.driftRadius, range: 0...0.3)
        }
    }

    // SIMD2 components don't expose Bindings directly — project each axis.
    private var centerX: Binding<Float> {
        Binding(get: { params.center.x }, set: { params.center.x = $0 })
    }
    private var centerY: Binding<Float> {
        Binding(get: { params.center.y }, set: { params.center.y = $0 })
    }
}
