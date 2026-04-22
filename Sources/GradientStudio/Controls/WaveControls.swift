import SwiftUI

struct WaveControls: View {
    @Binding var params: WaveParams

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            labelled("Amplitude", value: $params.amplitude, range: 0...0.4)
            labelled("Frequency", value: $params.frequency, range: 0.1...8)
            labelled("Speed",     value: $params.speed,     range: 0...1)
        }
    }
}
