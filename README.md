# GymApp — personal workout tracker

Local-first iPhone app: SQLite for storage, HealthKit for Apple Fitness sync,
no backend server, no third-party data sharing.

## Project structure

```
GymApp/
├── project.yml                      — XcodeGen spec; generates the .xcodeproj (no Mac needed)
├── GymApp/
│   ├── App/
│   │   ├── GymAppApp.swift          — app entry point
│   │   └── InfoPlist-additions.xml  — permission strings (also baked into project.yml)
│   ├── Models/
│   │   └── Models.swift             — Swift structs mirroring the SQL schema
│   ├── Database/
│   │   ├── schema.sql               — full DB schema (source of truth)
│   │   ├── Database.swift           — SQLite wrapper, runs schema.sql + seed data on first launch
│   │   └── ProgressionEngine.swift  — add/repeat/deload weight-progression logic
│   ├── HealthKit/
│   │   └── HealthKitManager.swift   — Apple Health read/write (HKWorkoutBuilder)
│   ├── Equipment/
│   │   ├── EquipmentIdentifier.swift — photo -> vision API -> equipment name/instructions
│   │   ├── CameraCaptureView.swift   — SwiftUI wrapper for camera capture
│   │   └── KeychainHelper.swift      — stores the API token outside of source
│   ├── Resources/
│   │   └── ExerciseDemos/           — real exercise photo pairs (public domain dataset)
│   └── Views/
│       ├── ContentView.swift        — root navigation
│       ├── TemplatePickerView.swift — home screen: pick today's workout
│       ├── WorkoutPreviewView.swift — review + swap exercises before starting
│       ├── WorkoutSessionView.swift — walks through a session's exercises
│       ├── LogSetView.swift         — capture-mode: log a set, minimal taps
│       ├── SessionSummaryView.swift — review-mode: PRs, chart, one notes field
│       ├── WeightEntryView.swift    — log body weight
│       └── APISettingsView.swift    — paste in the Hugging Face token
└── .github/workflows/build-ios.yml  — CI build: generates the Xcode project and compiles it
```

## Getting this into Xcode

You don't create the `.xcodeproj` by hand or in Xcode's GUI — `project.yml` at
the repo root defines the whole project declaratively, and the CI build
(`.github/workflows/build-ios.yml`) runs `xcodegen generate` on GitHub's free
macOS runner to produce `GymApp.xcodeproj` automatically, every push. This is
what makes the no-Mac path actually work end to end: nothing here requires you
to ever open Xcode's interface.

If you ever do get access to a Mac and want to open this project directly:
run `xcodegen generate` there too (`brew install xcodegen` first), then open
the resulting `GymApp.xcodeproj` — same file the CI runner produces.

## Where things stand

- **Schema**: fully defined in `schema.sql`, covers exercises, equipment, sessions,
  sets, templates, PRs, body measurements, and the machine-recognition log —
  seeded with a real 30+ exercise library and your actual Workout A/B program.
- **HealthKit**: `HealthKitManager` requests permissions, writes finished sessions
  via `HKWorkoutBuilder` with an estimated calorie count, and writes body weight —
  the pieces that make workouts and weigh-ins show up in Apple Fitness.
- **Capture-mode UI**: `LogSetView` — one exercise, big steppers (lbs, with a
  small-plate row for .25/.5/.75), auto rest timer, nothing else on screen.
- **Review-mode UI**: `SessionSummaryView` — PRs, a simple bar chart, one optional
  notes field, shown only after the session ends.
- **Preview + swap**: `WorkoutPreviewView` — review a session before starting,
  swap any exercise for an alternative in the same muscle group, or identify a
  new machine by photo via `EquipmentIdentifier` (Hugging Face vision API).
- **Progression**: `ProgressionEngine` — objective add/repeat/deload logic,
  including correct handling of assisted machines where more weight means less
  effort (e.g. the assisted pull-up path toward an unassisted pull-up).
- **Exercise demos**: `Resources/ExerciseDemos/` — real photo pairs (public
  domain, from the free-exercise-db dataset) for most of the library, shown as
  a looping preview before or during a set.

## Build/install path

- **No Mac, no budget (current setup)**: `.github/workflows/build-ios.yml`
  generates the Xcode project and builds an unsigned `.ipa` on GitHub's free
  macOS cloud runner. Sideload it onto your iPhone with SideStore (the free
  sideloading tool that's currently working, since AltStore has had ongoing
  reliability issues from Apple's periodic free-certificate revocations).
- **If you ever get Mac access**: `xcodegen generate` locally, open the
  resulting `.xcodeproj`, build and run over USB — same project either way.
