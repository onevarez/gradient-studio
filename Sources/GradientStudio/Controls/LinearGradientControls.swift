import SwiftUI

struct LinearGradientControls: View {
    @Binding var params: RenderParams

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ColorPicker("Color A", selection: colorBinding($params, \.lgColorA), supportsOpacity: false)
            ColorPicker("Color B", selection: colorBinding($params, \.lgColorB), supportsOpacity: false)
            labelled("Angle (rad)", value: $params.lgAngle, range: 0...(2 * .pi))
            labelled("Rotation (rad/s)", value: $params.lgRotationSpeed, range: -1...1)
        }
    }
}
