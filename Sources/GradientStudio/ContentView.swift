import SwiftUI

struct ContentView: View {
    @Bindable var state: AppState
    @State private var showExport = false

    var body: some View {
        HStack(spacing: 0) {
            MetalPreviewView(state: state)
                .frame(minWidth: 480, minHeight: 300)

            Divider()

            ScrollView {
                ControlsView(state: state)
                    .padding(16)
            }
            .frame(width: 320)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showExport = true
                } label: {
                    Label("Export…", systemImage: "arrow.down.circle")
                }
            }
        }
        .sheet(isPresented: $showExport) {
            ExportSettingsView(state: state, isPresented: $showExport)
        }
    }
}
