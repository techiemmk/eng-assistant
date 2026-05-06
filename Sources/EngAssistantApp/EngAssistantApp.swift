import SwiftUI

@main
struct EngAssistantApp: App {
    var body: some Scene {
        WindowGroup("EngAssistant") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    var body: some View {
        Text("EngAssistant — UI v1 in progress")
            .frame(minWidth: 600, minHeight: 400)
            .padding()
    }
}
