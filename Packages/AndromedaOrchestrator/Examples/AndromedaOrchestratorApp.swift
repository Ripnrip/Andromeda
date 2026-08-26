import SwiftUI
import AndromedaOrchestrator

// Minimal host. Drop this into an app target — the package ships the surface,
// the app ships the window.

@main
struct AndromedaOrchestratorApp: App {
    @State private var model = OrchestratorModel()

    var body: some Scene {
        WindowGroup {
            OrchestratorConsole(model: model)
                .frame(minWidth: 1180, minHeight: 760)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        #endif

        #if os(macOS)
        MenuBarExtra {
            HUDPanel(model: model)
                .orchestratorPalette()
                .frame(width: 292)
        } label: {
            Image(systemName: "triangle")
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}
