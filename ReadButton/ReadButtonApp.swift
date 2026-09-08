import SwiftUI

@main
struct ReadButtonApp: App {
    @StateObject private var model = ReadButtonModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}
