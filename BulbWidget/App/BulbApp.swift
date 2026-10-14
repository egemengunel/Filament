import SwiftUI

/// Host app for the widget. It only explains where to find the widget.
@main
struct BulbApp: App {
    var body: some Scene {
        Window("Bulb", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

private struct ContentView: View {
    @State private var state: BulbState?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(.yellow, in: Circle())
            VStack(spacing: 4) {
                Text("Bulb Widget")
                    .font(.title3.weight(.semibold))
                Text("Right-click your desktop, choose Edit Widgets, and search for Bulb.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let state {
                Label(
                    state.reachable ? "Connected to \(state.room) \(state.name)" : "Bridge not running",
                    systemImage: state.reachable ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                .font(.callout)
                .foregroundStyle(state.reachable ? .green : .orange)
            }
        }
        .padding(32)
        .frame(width: 360)
        .task { state = await BulbClient.state() }
    }
}
