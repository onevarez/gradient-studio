import SwiftUI

struct LinearGradientControls: View {
    @Binding var params: LinearParams

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ColorPicker("Color A", selection: colorBinding($params, \.colorA), supportsOpacity: false)
            ColorPicker("Color B", selection: colorBinding($params, \.colorB), supportsOpacity: false)
            labelled("Angle (rad)", value: $params.angle, range: 0...(2 * .pi))
            labelled("Rotation (rad/s)", value: $params.rotationSpeed, range: -1...1)
        }
    }
}
