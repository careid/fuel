# Fuel

Claude-powered nutrition and health tracker for iOS. Voice, photo, and video meal logging with Apple HealthKit integration and smart contextual reminders.

## Status

**Pre-development** - Architecture and scoping phase.

## Concept

Fuel is a personal nutrition tracker that uses Claude's vision and language capabilities to make food logging as low-friction as possible. Snap a photo, leave a voice note, or just type "had my usual breakfast" - Claude handles the extraction and estimation.

### Core Features (MVP)

1. **Multi-modal meal logging** - Photo, voice, video, quick-add, manual
2. **Claude-powered extraction** - Identifies foods, estimates portions and macros from any input
3. **Running daily totals** - Calories, protein, with progress toward goals
4. **Apple HealthKit integration** - Sleep, steps, weight (via Renpho → HealthKit), workouts
5. **Sleep-nutrition correlation** - Surface patterns between sleep quality and eating habits
6. **Smart reminders** - Geofenced (kitchen detection), time-based, post-workout, evening summary
7. **Conversational refinement** - "Actually that was 8oz salmon" → updated estimates

### Future

- Gentle workout suggestions based on sleep/recovery data
- Partner visibility / accountability
- Weekly AI-generated insights
- Workout-day calorie auto-adjustment
- Meal pattern learning (your "usual" orders)

## Tech Stack

- **SwiftUI** - Native iOS UI
- **HealthKit** - Sleep, steps, weight, workouts, heart rate
- **CoreLocation** - Geofenced kitchen reminders
- **Claude API (Anthropic)** - Vision, language, conversational UI
- **SwiftData** - Local-first on-device storage
- **Apple Speech / Whisper** - Voice → text preprocessing

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed technical design.
