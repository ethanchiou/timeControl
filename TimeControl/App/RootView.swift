import SwiftUI
import TimeControlCore

struct RootView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("TimeControl")
                .font(.largeTitle.bold())
            Text("Today is \(DayKey.today().description) (\(DayKey.today().weekday.name))")
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}

#Preview {
    RootView()
}
