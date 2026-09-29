import SwiftUI

// Training Brain for Apple Watch — today's gym workout from the Training Brain app,
// one set per screen, rest countdowns, recorded as a Strength workout in Apple
// Health, and every finished set sent back to the app as you go.
@main
struct TrainingBrainApp: App {
    @StateObject private var model = WorkoutModel()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
        }
    }
}
