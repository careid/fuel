import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selectedTab: Tab = .today
    @State private var showLogMeal = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                mainTabs
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut(duration: 0.4), value: hasCompletedOnboarding)
    }

    private var mainTabs: some View {
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
