import SwiftUI
import AppKit
import simd

extension Color {
    /// Build a SwiftUI Color from sRGB components packed in a SIMD4<Float>.
    static func fromSIMD4(_ v: SIMD4<Float>) -> Color {
        Color(
            .sRGB,
            red: Double(v.x),
            green: Double(v.y),
            blue: Double(v.z),
            opacity: Double(v.w)
        )
    }

    /// Resolve this Color to sRGB components for shader consumption.
    func toSIMD4() -> SIMD4<Float> {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        return SIMD4(
            Float(ns.redComponent),
            Float(ns.greenComponent),
            Float(ns.blueComponent),
            Float(ns.alphaComponent)
        )
    }
}

/// Helper to bind a SwiftUI `Color` control to a `SIMD4<Float>` stored anywhere
/// in a value-typed tree (e.g. inside a layer's params struct).
func colorBinding<Root>(_ root: Binding<Root>,
                        _ keyPath: WritableKeyPath<Root, SIMD4<Float>>) -> Binding<Color> {
    Binding(
        get: { Color.fromSIMD4(root.wrappedValue[keyPath: keyPath]) },
        set: { root.wrappedValue[keyPath: keyPath] = $0.toSIMD4() }
    )
}
