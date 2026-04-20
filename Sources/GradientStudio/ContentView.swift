import SwiftUI

struct ContentView: View {
    @Bindable var state: AppState
    @State private var showExport = false
    @State private var pasteError: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Picker("Aspect", selection: $state.previewAspect) {
                    ForEach(PreviewAspect.allCases) { a in
                        Text(a.label).tag(a)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
                .padding(8)

                ZStack {
                    Color.black
                    Group {
                        if let ratio = state.previewAspect.ratio {
                            MetalPreviewView(state: state)
                                .aspectRatio(ratio, contentMode: .fit)
                        } else {
                            MetalPreviewView(state: state)
                        }
                    }
                    .padding(12)
                }
                .frame(minWidth: 480, minHeight: 300)
            }

            Divider()

            ScrollView {
                ControlsView(state: state)
                    .padding(16)
            }
            .frame(width: 320)
        }
        .onChange(of: state.params) { oldValue, _ in
            state.scheduleCheckpoint(oldValue: oldValue)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: state.undo) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!state.canUndo)
                .help("Undo last change (⌘Z)")
                .keyboardShortcut("z", modifiers: [.command])
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: state.redo) {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!state.canRedo)
                .help("Redo (⇧⌘Z)")
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: copyPreset) {
                    Label("Copy Preset", systemImage: "doc.on.doc")
                }
                .help("Copy the current gradient as JSON (⇧⌘C)")
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: pastePreset) {
                    Label("Paste Preset", systemImage: "doc.on.clipboard")
                }
                .help("Paste a GradientStudio preset from the clipboard (⇧⌘V)")
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
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
        .alert("Paste failed",
               isPresented: Binding(
                get: { pasteError != nil },
                set: { if !$0 { pasteError = nil } }
               ),
               presenting: pasteError
        ) { _ in
            Button("OK", role: .cancel) { pasteError = nil }
        } message: { err in
            Text(err)
        }
    }

    private func copyPreset() {
        do {
            try PresetPasteboard.copy(state.params)
        } catch {
            // Copy should effectively never fail (encoder is deterministic), but
            // surface the error through the same alert if it somehow does.
            pasteError = error.localizedDescription
        }
    }

    private func pastePreset() {
        do {
            let preset = try PresetPasteboard.paste()
            try preset.apply(to: &state.params)
        } catch {
            pasteError = error.localizedDescription
        }
    }
}
