import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .today
    @State private var showLogMeal = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                TodayView(showLogMeal: $showLogMeal)
                    .tabItem {
                        Label("Today", systemImage: "flame.fill")
                    }
                    .tag(Tab.today)

                HistoryView()
                    .tabItem {
                        Label("History", systemImage: "calendar")
                    }
                    .tag(Tab.history)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(Tab.settings)
            }
        }
        .sheet(isPresented: $showLogMeal) {
            LogMealView()
        }
    }
}

enum Tab {
    case today
    case history
    case settings
}
