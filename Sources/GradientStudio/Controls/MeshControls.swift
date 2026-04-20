import SwiftUI

struct MeshControls: View {
    @Binding var params: RenderParams

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 6),
        count: GradientRendererLimits.meshGridWidth
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Style", selection: $params.meshStyle) {
                Text("Grid").tag(MeshStyle.grid)
                Text("Blobs").tag(MeshStyle.blobs)
                Text("Smoke").tag(MeshStyle.smoke)
            }
            .pickerStyle(.segmented)

            labelled("Opacity",     value: $params.meshOpacity,     range: 0...1)
            labelled("Drift speed", value: $params.meshDriftSpeed, range: 0...1.5)

            HStack {
                Text(params.meshStyle == .grid
                     ? "\(GradientRendererLimits.meshGridWidth)×\(GradientRendererLimits.meshGridHeight) grid"
                     : "\(params.meshPoints.count) blobs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reseed") { params.reseedMeshPoints() }
            }

            Divider()

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach($params.meshPoints) { $pt in
                    ColorPicker("", selection: Binding(
                        get: { Color.fromSIMD4(pt.color) },
                        set: { pt.color = $0.toSIMD4() }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }
            }
        }
    }
}
