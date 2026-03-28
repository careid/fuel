# Architecture

## System Overview

```
┌─────────────────────────────────────────────┐
│                  iOS App                     │
│                                              │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐  │
│  │ SwiftUI  │  │ SwiftData│  │ HealthKit │  │
│  │  Views   │  │  Store   │  │  Manager  │  │
│  └────┬─────┘  └────┬─────┘  └─────┬─────┘  │
│       │              │              │         │
│  ┌────┴──────────────┴──────────────┴─────┐  │
│  │           Domain Layer                  │  │
│  │  NutritionEngine / HealthDataManager   │  │
│  └────────────────┬───────────────────────┘  │
│                   │                          │
│  ┌────────────────┴───────────────────────┐  │
│  │         Claude Service                  │  │
│  │  (Photo → macros, Voice → macros,      │  │
│  │   conversational refinement,            │  │
│  │   weekly insights)                      │  │
│  └────────────────┬───────────────────────┘  │
│                   │                          │
│  ┌────────────────┴───────────────────────┐  │
│  │       CoreLocation / Notifications      │  │
│  │  (Geofence reminders, time-based,       │  │
│  │   post-workout triggers)                │  │
│  └────────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
                    │
                    ▼
         ┌──────────────────┐
         │  Anthropic API   │
         │  (Claude Sonnet) │
         └──────────────────┘
```

## Core Modules

### 1. Input Processing Pipeline

All inputs flow through a unified pipeline:

```
Photo/Voice/Video/Text
        │
        ▼
  ┌─────────────┐
  │ Preprocessor │  ← Voice: Apple Speech → text
  │              │  ← Photo: resize/compress
  │              │  ← Video: extract key frames + audio
  └──────┬──────┘
         │
         ▼
  ┌─────────────┐
  │   Claude     │  ← Structured extraction prompt
  │   Service    │  ← Returns: [FoodItem] with macros
  └──────┬──────┘
         │
         ▼
  ┌─────────────┐
  │  Nutrition   │  ← Validates, stores, updates totals
  │  Engine      │  ← Triggers reminder recalculation
  └─────────────┘
```

### 2. Data Models (SwiftData)

```swift
@Model class DayLog {
    let date: Date                    // Calendar day
    var meals: [Meal]
    var calorieTarget: Int
    var proteinTarget: Int            // grams
    // Computed from meals
    var totalCalories: Int
    var totalProtein: Int
}

@Model class Meal {
    let id: UUID
    let timestamp: Date
    var mealType: MealType            // breakfast, lunch, dinner, snack
    var items: [FoodItem]
    var inputType: InputType          // photo, voice, video, manual, quick
    var rawInput: Data?               // Original photo/audio for reference
    var claudeConversation: [Message] // For refinement ("actually 8oz")
}

@Model class FoodItem {
    let name: String
    var calories: Int
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var quantity: String              // "2 eggs", "1 cup", "6oz"
    var confidence: Confidence        // high, medium, low
}

@Model class HealthSnapshot {
    let date: Date
    var sleepDuration: TimeInterval?
    var sleepStages: SleepStageData?
    var steps: Int?
    var restingHeartRate: Int?
    var weight: Double?               // from Renpho via HealthKit
    var activeCalories: Int?
    var workouts: [WorkoutSummary]
}

@Model class UserSettings {
    var calorieTarget: Int            // default 2200
    var proteinTarget: Int            // default 160g
    var homeLocation: CLLocationCoordinate2D?
    var kitchenGeofenceRadius: Double // default 15m
    var reminderPreferences: ReminderPreferences
}
```

### 3. Claude Service

Single service handling all Claude interactions:

**Meal extraction prompt pattern:**
```
System: You are a nutrition assistant. Extract food items with macro
estimates from the user's input. Return structured JSON.

Given the user's meal input, identify each food item and estimate:
- Calories
- Protein (g), Carbs (g), Fat (g)
- Portion size
- Confidence level (high/medium/low)

Be conversational - if something is ambiguous, note it.
Return JSON matching the FoodItem schema.
```

**Conversational refinement:**
- Maintains a short conversation history per meal
- User can correct estimates ("more like 8oz", "I also had a roll")
- Claude reprocesses with corrections and returns updated totals

**Model choice:** Claude Sonnet 4.6 for meal extraction (fast, cheap, good with vision). Opus for weekly insights if we want deeper analysis later.

### 4. HealthKit Manager

Reads (never writes) from HealthKit:

```swift
class HealthDataManager {
    // Permissions requested on first launch
    let readTypes: Set<HKObjectType> = [
        .sleepAnalysis,
        .stepCount,
        .bodyMass,
        .activeEnergyBurned,
        .restingHeartRate,
        .workoutType
    ]

    // Background delivery for weight updates
    // (Renpho syncs → HealthKit → our app gets notified)
    func enableBackgroundDelivery()

    // Daily snapshot aggregation
    func fetchDailySnapshot(for date: Date) -> HealthSnapshot
}
```

### 5. Reminder System

Three trigger types, all managed by a single `ReminderManager`:

**Geofenced (kitchen):**
- User sets home location in settings (or auto-detected)
- CoreLocation monitors region entry
- Suppressed if meal logged within last 2 hours
- Only fires during meal windows (7am-9pm)

**Time-based:**
- Configurable meal windows with ±30min tolerance
- "No lunch logged and it's 1:30pm" → gentle notification
- Backs off if user is logging consistently

**Event-driven:**
- Post-workout: "You burned ~X cal. Recovery meal?"
- Evening summary: "You're at Xg protein. A shake would close the gap."
- Low sleep: "Rough night - be mindful of extra snacking today."

### 6. Privacy Model

- All food logs, health data, and settings stored **on-device only** (SwiftData)
- Only meal descriptions/photos sent to Claude API for processing
- No cloud database, no account system (MVP)
- Health data never leaves the device
- Claude conversations are ephemeral (not stored on Anthropic's side with API usage)

## Screen Map

```
App Launch
    │
    ├── Today (main tab)
    │   ├── Daily dashboard (calories, protein, health stats)
    │   ├── Meal list with expandable details
    │   ├── Quick input bar (photo/voice/text)
    │   └── Claude chat for refinement
    │
    ├── History (tab)
    │   ├── Calendar view with daily summaries
    │   ├── Weekly protein/calorie trends
    │   └── Sleep-nutrition correlation charts
    │
    ├── Log Meal (floating action / input bar)
    │   ├── Camera (photo capture)
    │   ├── Voice recorder
    │   ├── Text input
    │   ├── Quick-add (favorites/recents)
    │   └── Claude conversation view
    │
    └── Settings (tab)
        ├── Calorie & protein targets
        ├── Home/kitchen location
        ├── Reminder preferences
        ├── HealthKit permissions
        └── Claude API key
```

## File Structure

```
Fuel/
├── App/
│   ├── FuelApp.swift              # App entry point
│   └── ContentView.swift          # Tab navigation
│
├── Features/
│   ├── Today/
│   │   ├── TodayView.swift        # Main dashboard
│   │   ├── DailySummaryCard.swift  # Calories/protein progress
│   │   ├── HealthStatsCard.swift   # Sleep, steps, weight
│   │   └── MealListView.swift     # Today's meals
│   │
│   ├── LogMeal/
│   │   ├── LogMealView.swift      # Input method selection
│   │   ├── PhotoCaptureView.swift # Camera interface
│   │   ├── VoiceInputView.swift   # Voice recording
│   │   ├── TextInputView.swift    # Manual text entry
│   │   ├── QuickAddView.swift     # Favorites/recents
│   │   └── MealReviewView.swift   # Claude's extraction + refinement chat
│   │
│   ├── History/
│   │   ├── HistoryView.swift      # Calendar + trends
│   │   ├── DayDetailView.swift    # Single day breakdown
│   │   └── TrendsView.swift       # Charts (sleep-nutrition correlation)
│   │
│   └── Settings/
│       ├── SettingsView.swift
│       ├── TargetsView.swift      # Calorie/protein goals
│       ├── LocationView.swift     # Kitchen geofence setup
│       └── RemindersView.swift    # Notification preferences
│
├── Services/
│   ├── ClaudeService.swift        # Anthropic API client
│   ├── HealthDataManager.swift    # HealthKit reads
│   ├── ReminderManager.swift      # Geofence + time + event triggers
│   ├── NutritionEngine.swift      # Totals, targets, calculations
│   └── SpeechService.swift        # Voice → text preprocessing
│
├── Models/
│   ├── DayLog.swift
│   ├── Meal.swift
│   ├── FoodItem.swift
│   ├── HealthSnapshot.swift
│   └── UserSettings.swift
│
├── Shared/
│   ├── Extensions/
│   ├── Components/                # Reusable SwiftUI components
│   └── Theme.swift                # Colors, typography
│
└── Resources/
    └── Assets.xcassets
```

## MVP Milestones

### M1: Core Logging ✅ CLOSED
- [x] SwiftData models + persistence
- [x] Today dashboard with manual text input
- [x] Claude Service: text → structured food items
- [x] Running calorie/protein totals
- [x] Basic meal list view

### M2: Multi-Modal Input ✅ CLOSED
- [x] Photo capture → Claude Vision extraction
- [x] Voice recording → Apple Speech → text → Claude extraction
- [x] Conversational refinement ("actually 8oz salmon")
- [x] Quick-add from recent meals

### M3: HealthKit Integration ✅ CLOSED
- [x] HealthKit permission flow
- [x] Sleep data display on dashboard
- [x] Steps + active calories
- [x] Weight from Renpho (via HealthKit)
- [x] Daily health snapshot persistence

### M4: Smart Reminders (Week 7-8)
- [ ] Kitchen geofence setup + monitoring
- [ ] Time-based meal window reminders
- [ ] Post-workout reminders (HealthKit workout detection)
- [ ] Evening protein gap summary
- [ ] Adaptive frequency (back off when consistent)

### M5: Insights & Polish (Week 9-10)
- [ ] Sleep-nutrition correlation view
- [ ] Weekly trends charts
- [ ] Calendar history view
- [ ] TestFlight deployment
- [ ] Onboarding flow (targets, HealthKit permissions, kitchen location)
