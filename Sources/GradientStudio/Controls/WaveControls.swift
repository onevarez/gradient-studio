import SwiftUI

struct WaveControls: View {
    @Binding var params: RenderParams

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            labelled("Amplitude", value: $params.waveAmplitude, range: 0...0.4)
            labelled("Frequency", value: $params.waveFrequency, range: 0.1...8)
            labelled("Speed",     value: $params.waveSpeed,     range: 0...1)
        }
    }
}
