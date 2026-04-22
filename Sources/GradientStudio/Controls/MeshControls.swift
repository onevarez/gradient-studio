import SwiftUI

struct MeshControls: View {
    @Binding var params: MeshParams

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 6),
        count: GradientRendererLimits.meshGridWidth
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Style", selection: $params.style) {
                Text("Grid").tag(MeshStyle.grid)
                Text("Blobs").tag(MeshStyle.blobs)
                Text("Smoke").tag(MeshStyle.smoke)
            }
            .pickerStyle(.segmented)

            labelled("Opacity",     value: $params.opacity,     range: 0...1)
            labelled("Drift speed", value: $params.driftSpeed, range: 0...1.5)

            HStack {
                Text(params.style == .grid
                     ? "\(GradientRendererLimits.meshGridWidth)×\(GradientRendererLimits.meshGridHeight) grid"
                     : "\(params.points.count) blobs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reseed") { params.reseed() }
            }

            HStack(spacing: 6) {
                Button {
                    params.cycleClockwise()
                } label: {
                    Label("Cycle", systemImage: "arrow.clockwise")
                }
                .help("Rotate grid colors clockwise (period 12)")

                Button {
                    params.blackoutSides()
                } label: {
                    Label("Sides", systemImage: "rectangle.lefthalf.filled")
                }
                .help("Black out left & right columns")

                Button {
                    params.blackoutTopBottom()
                } label: {
                    Label("Top / Bot", systemImage: "rectangle.tophalf.filled")
                }
                .help("Black out top & bottom rows")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Divider()

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach($params.points) { $pt in
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
