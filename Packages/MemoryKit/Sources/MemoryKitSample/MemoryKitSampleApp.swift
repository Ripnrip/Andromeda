import SwiftUI
import MemoryKit

@main
struct MemoryKitSampleApp: App {
    var body: some Scene {
        WindowGroup {
            MemoryKitSampleView()
                .frame(minWidth: 520, minHeight: 420)
        }
        .windowResizability(.contentSize)
    }
}
