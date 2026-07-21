import SwiftUI
import ComposableArchitecture
import MemoryKit
import AnimaCore
import AnimaKnowledge
import AnimaIndexing

@main
struct AnimaSampleApp: App {
    var body: some Scene {
        WindowGroup {
            AnimaSampleView()
                .frame(minWidth: 560, minHeight: 480)
        }
        .windowResizability(.contentSize)
    }
}
