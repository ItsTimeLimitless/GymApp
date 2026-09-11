import Foundation
import SQLite3

/// SQLite's SQLITE_TRANSIENT isn't imported automatically into Swift —
/// this tells sqlite3_bind_text/_blob to copy the buffer immediately,
/// which is what you want when binding a Swift String's temporary
/// C-string pointer. Shared by every file that binds text params.
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thin wrapper around SQLite's C API — no external dependency needed.
/// If you'd rather use SwiftData/CoreData instead, this file is the only
/// one you'd need to swap out; Models.swift and the views don't care
/// how persistence works underneath.
final class Database {
    static let shared = Database()

    /// Visible, on-device record of what happened during setup — added
    /// because print() output is invisible once the app is sideloaded
    /// (no console access), so this is the only way to actually see
    /// what went wrong without a Mac/Xcode attached to the phone.
    static var diagnosticLog: [String] = []
    private static func log(_ message: String) {
        diagnosticLog.append(message)
        print(message)
    }

    private var db: OpaquePointer?
    private let seededFlagKey = "gymapp.didSeedDatabase"

    private init() {
        openDatabase()
        runSchemaIfNeeded()
        runSeedIfNeeded()
        checkDemoPhotosBundled()
    }

    /// One known demo photo, checked at launch — a canary for whether
    /// the photos actually made it into this build. Two earlier
    /// approaches (a loose schema.sql file, then a proper .xcassets
    /// catalog) both silently failed on real hardware — the asset
    /// catalog specifically because actool wasn't running at all in
    /// this unsigned CI build (confirmed: no Assets.car in the bundle).
    /// This version is copied straight into the .app bundle by the CI
    /// packaging script itself, bypassing Xcode's resource pipeline
    /// entirely, so there's no build-phase behavior left to depend on.
    private func checkDemoPhotosBundled() {
        if Bundle.main.url(forResource: "0", withExtension: "jpg", subdirectory: "PhotoAssets/Barbell_Full_Squat") != nil {
            Self.log("✅ Exercise demo photos found in bundle")
        } else {
            Self.log("❌ Exercise demo photos NOT found — Preview buttons will show \"no demo photo\" for everything")
            if let resourcePath = Bundle.main.resourcePath,
               let contents = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) {
                Self.log("ℹ️ Top-level bundle contents: \(contents.prefix(15).joined(separator: ", "))")
            }
        }
    }

    private func openDatabase() {
        let fileURL = try! FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("gymapp.sqlite")

        if sqlite3_open(fileURL.path, &db) != SQLITE_OK {
            Self.log("❌ Unable to open database at \(fileURL.path)")
        } else {
            Self.log("✅ Database opened at \(fileURL.path)")
        }
    }

    /// Runs the schema exactly once. Safe to call every launch — the
    /// UserDefaults flag guards against re-running it, and every
    /// statement uses CREATE TABLE IF NOT EXISTS anyway.
    ///
    /// This is embedded directly as a Swift string (same approach as
    /// seedSQL below) rather than loaded from a bundled schema.sql file
    /// at runtime — a real device test showed XcodeGen wasn't reliably
    /// copying that loose file into the app bundle, which silently
    /// broke everything downstream (no tables → seeding fails → every
    /// screen looks empty). Baking it into source removes that whole
    /// failure mode: it's guaranteed present since it's compiled in,
    /// not looked up on disk at runtime.
    private func runSchemaIfNeeded() {
        var errorMessage: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, Self.schemaSQL, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown error"
            Self.log("❌ Schema execution failed: \(message)")
        } else {
            Self.log("✅ Schema executed OK")
        }
    }

    private static let schemaSQL = """
    -- Reference data ------------------------------------------------

    CREATE TABLE IF NOT EXISTS muscle_groups (
        id INTEGER PRIMARY KEY,
        name TEXT UNIQUE NOT NULL,
        body_region TEXT
    );

    CREATE TABLE IF NOT EXISTS equipment (
        id INTEGER PRIMARY KEY,
        name TEXT UNIQUE NOT NULL,
        category TEXT,
        photo_local_path TEXT,
        usage_instructions TEXT,
        safety_notes TEXT,
        identified_via_photo INTEGER DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS exercises (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        exercise_type TEXT CHECK(exercise_type IN ('strength','cardio','mobility')),
        equipment_id INTEGER REFERENCES equipment(id),
        primary_muscle_id INTEGER REFERENCES muscle_groups(id),
        difficulty TEXT CHECK(difficulty IN ('beginner','intermediate','advanced')),
        instructions TEXT,
        video_url TEXT,
        demo_asset_id TEXT,
        increment_kg REAL DEFAULT 2.5,
        is_custom INTEGER DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS exercise_secondary_muscles (
        exercise_id INTEGER REFERENCES exercises(id),
        muscle_group_id INTEGER REFERENCES muscle_groups(id),
        PRIMARY KEY (exercise_id, muscle_group_id)
    );

    -- Programming -----------------------------------------------------

    CREATE TABLE IF NOT EXISTS workout_templates (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        goal TEXT,
        notes TEXT
    );

    CREATE TABLE IF NOT EXISTS workout_template_exercises (
        id INTEGER PRIMARY KEY,
        template_id INTEGER REFERENCES workout_templates(id),
        exercise_id INTEGER REFERENCES exercises(id),
        target_sets INTEGER,
        target_reps_min INTEGER DEFAULT 8,
        target_reps_max INTEGER DEFAULT 10,
        order_index INTEGER
    );

    -- Actual logged activity -------------------------------------------

    CREATE TABLE IF NOT EXISTS workout_sessions (
        id INTEGER PRIMARY KEY,
        template_id INTEGER REFERENCES workout_templates(id),
        start_time TEXT NOT NULL,
        end_time TEXT,
        total_calories REAL,
        avg_heart_rate REAL,
        notes TEXT,
        healthkit_uuid TEXT
    );

    CREATE TABLE IF NOT EXISTS workout_sets (
        id INTEGER PRIMARY KEY,
        session_id INTEGER REFERENCES workout_sessions(id),
        exercise_id INTEGER REFERENCES exercises(id),
        set_number INTEGER,
        reps INTEGER,
        weight_kg REAL,
        rpe REAL,
        is_warmup INTEGER DEFAULT 0,
        rest_seconds INTEGER,
        completed_at TEXT DEFAULT CURRENT_TIMESTAMP
    );

    -- Progress tracking -------------------------------------------------

    CREATE TABLE IF NOT EXISTS body_measurements (
        id INTEGER PRIMARY KEY,
        recorded_at TEXT DEFAULT CURRENT_TIMESTAMP,
        weight_kg REAL,
        body_fat_pct REAL,
        waist_cm REAL,
        chest_cm REAL,
        arm_cm REAL,
        thigh_cm REAL,
        photo_path TEXT,
        source TEXT DEFAULT 'manual'
    );

    CREATE TABLE IF NOT EXISTS personal_records (
        id INTEGER PRIMARY KEY,
        exercise_id INTEGER REFERENCES exercises(id),
        record_type TEXT CHECK(record_type IN ('1rm','max_reps','max_volume')),
        value REAL,
        achieved_at TEXT DEFAULT CURRENT_TIMESTAMP,
        session_id INTEGER REFERENCES workout_sessions(id)
    );

    CREATE TABLE IF NOT EXISTS machine_recognition_log (
        id INTEGER PRIMARY KEY,
        photo_path TEXT,
        equipment_id INTEGER REFERENCES equipment(id),
        raw_llm_response TEXT,
        confidence REAL,
        queried_at TEXT DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_sets_session ON workout_sets(session_id);
    CREATE INDEX IF NOT EXISTS idx_sessions_start ON workout_sessions(start_time);
    CREATE INDEX IF NOT EXISTS idx_exercises_equipment ON exercises(equipment_id);
    """

    /// Seeds the real Workout A / Workout B program worked out earlier —
    /// full-body, alternating, 3x/week, for recomposition — plus a
    /// broader exercise library (11 muscle groups, ~30 exercises) so
    /// the "Swap" option in the preview screen has real alternatives to
    /// offer, not just the one exercise per muscle group we started
    /// with. Workout A/B themselves are unchanged — still 4 exercises
    /// each — this only adds variety behind the swap button.
    private func runSeedIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seededFlagKey) else {
            Self.log("ℹ️ Seed already ran previously (flag set) — skipping")
            return
        }
        var errorMessage: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, Self.seedSQL, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown error"
            Self.log("❌ Seed data failed: \(message)")
            return
        }
        UserDefaults.standard.set(true, forKey: seededFlagKey)
        var count = 0
        query("SELECT COUNT(*) FROM workout_templates") { statement in
            count = Int(sqlite3_column_int(statement, 0))
        }
        Self.log("✅ Seed executed OK — \(count) workout_templates rows now in DB")
    }

    private static let seedSQL = """
    INSERT INTO muscle_groups (name, body_region) VALUES
      ('Quads', 'Legs'),
      ('Hamstrings', 'Legs'),
      ('Glutes', 'Legs'),
      ('Calves', 'Legs'),
      ('Chest', 'Push'),
      ('Shoulders', 'Push'),
      ('Triceps', 'Push'),
      ('Lats', 'Pull'),
      ('Back', 'Pull'),
      ('Biceps', 'Pull'),
      ('Core', 'Core');

    INSERT INTO equipment (name, category) VALUES
      ('Barbell', 'free weight'),
      ('Dumbbell', 'free weight'),
      ('EZ curl bar', 'free weight'),
      ('Cable machine', 'machine'),
      ('Crunch machine', 'machine'),
      ('Leg press machine', 'machine'),
      ('Leg extension machine', 'machine'),
      ('Leg curl machine', 'machine'),
      ('Calf raise machine', 'machine'),
      ('Smith machine', 'machine'),
      ('Machine', 'machine'),
      ('Pull-up bar', 'bodyweight'),
      ('Assisted pull-up machine', 'machine'),
      ('Dip station', 'bodyweight');

    INSERT INTO exercises (name, exercise_type, equipment_id, primary_muscle_id, difficulty, instructions, demo_asset_id, increment_kg) VALUES
      ('Barbell back squat', 'strength', (SELECT id FROM equipment WHERE name = 'Barbell'), (SELECT id FROM muscle_groups WHERE name = 'Quads'), 'beginner', 'Bar on upper back, feet shoulder width, sit hips back and down, drive up through the heels.', 'Barbell_Full_Squat', 5.0),
      ('Leg press', 'strength', (SELECT id FROM equipment WHERE name = 'Leg press machine'), (SELECT id FROM muscle_groups WHERE name = 'Quads'), 'beginner', 'Feet shoulder width on the platform, lower until knees reach about 90 degrees, press back up.', 'Leg_Press', 10.0),
      ('Dumbbell goblet squat', 'strength', (SELECT id FROM equipment WHERE name = 'Dumbbell'), (SELECT id FROM muscle_groups WHERE name = 'Quads'), 'beginner', 'Hold one dumbbell at chest height, squat down keeping the chest up, drive through the heels.', 'Goblet_Squat', 2.5),
      ('Leg extension', 'strength', (SELECT id FROM equipment WHERE name = 'Leg extension machine'), (SELECT id FROM muscle_groups WHERE name = 'Quads'), 'beginner', 'Sit with the pad above the ankles, extend the knees fully, control the return.', 'Leg_Extensions', 5.0),

      ('Barbell deadlift', 'strength', (SELECT id FROM equipment WHERE name = 'Barbell'), (SELECT id FROM muscle_groups WHERE name = 'Hamstrings'), 'beginner', 'Bar over mid foot, flat back, drive through the floor to stand tall.', 'Barbell_Deadlift', 5.0),
      ('Romanian deadlift', 'strength', (SELECT id FROM equipment WHERE name = 'Barbell'), (SELECT id FROM muscle_groups WHERE name = 'Hamstrings'), 'beginner', 'Soft knees, push the hips back keeping the bar close to the legs, feel the hamstring stretch, drive hips forward to stand.', 'Romanian_Deadlift', 5.0),
      ('Leg curl', 'strength', (SELECT id FROM equipment WHERE name = 'Leg curl machine'), (SELECT id FROM muscle_groups WHERE name = 'Hamstrings'), 'beginner', 'Lie face down, curl the pad toward the glutes, control the return.', 'Ball_Leg_Curl', 5.0),

      ('Hip thrust', 'strength', (SELECT id FROM equipment WHERE name = 'Barbell'), (SELECT id FROM muscle_groups WHERE name = 'Glutes'), 'beginner', 'Upper back on a bench, bar over the hips, drive the hips up until the body is a straight line, squeeze at the top.', 'Barbell_Hip_Thrust', 5.0),
      ('Cable kickback', 'strength', (SELECT id FROM equipment WHERE name = 'Cable machine'), (SELECT id FROM muscle_groups WHERE name = 'Glutes'), 'beginner', 'Ankle cuff attachment, kick the leg back and up, squeeze the glute, control the return.', 'Glute_Kickback', 2.5),

      ('Standing calf raise', 'strength', (SELECT id FROM equipment WHERE name = 'Calf raise machine'), (SELECT id FROM muscle_groups WHERE name = 'Calves'), 'beginner', 'Rise onto the toes as high as possible, pause, lower under control past parallel.', 'Standing_Calf_Raises', 5.0),
      ('Seated calf raise', 'strength', (SELECT id FROM equipment WHERE name = 'Calf raise machine'), (SELECT id FROM muscle_groups WHERE name = 'Calves'), 'beginner', 'Knees bent under the pad, rise onto the toes, pause, lower under control.', 'Barbell_Seated_Calf_Raise', 5.0),

      ('Barbell bench press', 'strength', (SELECT id FROM equipment WHERE name = 'Barbell'), (SELECT id FROM muscle_groups WHERE name = 'Chest'), 'beginner', 'Lie on the bench, lower the bar to mid chest, press back up to full extension.', 'Barbell_Bench_Press_-_Medium_Grip', 2.5),
      ('Dumbbell bench press', 'strength', (SELECT id FROM equipment WHERE name = 'Dumbbell'), (SELECT id FROM muscle_groups WHERE name = 'Chest'), 'beginner', 'Lie on the bench, press both dumbbells up over the chest, lower under control.', 'Dumbbell_Bench_Press', 2.5),
      ('Incline dumbbell press', 'strength', (SELECT id FROM equipment WHERE name = 'Dumbbell'), (SELECT id FROM muscle_groups WHERE name = 'Chest'), 'beginner', 'Bench set to a slight incline, press both dumbbells up over the upper chest, lower under control.', 'Incline_Dumbbell_Press', 2.5),
      ('Push-up', 'strength', NULL, (SELECT id FROM muscle_groups WHERE name = 'Chest'), 'beginner', 'Hands under shoulders, lower the chest to the floor keeping a straight line, press back up.', 'Decline_Push-Up', 0),

      ('Overhead press', 'strength', (SELECT id FROM equipment WHERE name = 'Barbell'), (SELECT id FROM muscle_groups WHERE name = 'Shoulders'), 'beginner', 'Press the bar from shoulders to full extension overhead, ribs down.', 'Standing_Military_Press', 2.5),
      ('Dumbbell shoulder press', 'strength', (SELECT id FROM equipment WHERE name = 'Dumbbell'), (SELECT id FROM muscle_groups WHERE name = 'Shoulders'), 'beginner', 'Press both dumbbells from shoulder height to full extension overhead.', 'Dumbbell_Shoulder_Press', 2.5),
      ('Lateral raise', 'strength', (SELECT id FROM equipment WHERE name = 'Dumbbell'), (SELECT id FROM muscle_groups WHERE name = 'Shoulders'), 'beginner', 'Raise both dumbbells out to the sides to shoulder height, control the return.', 'Cable_Seated_Lateral_Raise', 1.0),

      ('Cable pushdown', 'strength', (SELECT id FROM equipment WHERE name = 'Cable machine'), (SELECT id FROM muscle_groups WHERE name = 'Triceps'), 'beginner', 'Elbows tucked at your sides, push the bar down to full extension, control the return.', 'Triceps_Pushdown', 2.5),
      ('Dip', 'strength', (SELECT id FROM equipment WHERE name = 'Dip station'), (SELECT id FROM muscle_groups WHERE name = 'Triceps'), 'beginner', 'Lower the body until the elbows reach about 90 degrees, press back up to full extension.', 'Dips_-_Triceps_Version', 0),

      ('Lat pulldown', 'strength', (SELECT id FROM equipment WHERE name = 'Cable machine'), (SELECT id FROM muscle_groups WHERE name = 'Lats'), 'beginner', 'Grip the bar wide, pull down to upper chest, control the return.', 'Wide-Grip_Lat_Pulldown', 2.5),
      ('Assisted pull-up machine', 'strength', (SELECT id FROM equipment WHERE name = 'Assisted pull-up machine'), (SELECT id FROM muscle_groups WHERE name = 'Lats'), 'beginner', 'Kneel or stand on the platform, pull the chin over the bar, control the way down. Lower the assist weight over time as you get stronger — once it reaches 0, switch to real pull-ups.', 'Band_Assisted_Pull-Up', -5.0),
      ('Pull-up', 'strength', (SELECT id FROM equipment WHERE name = 'Pull-up bar'), (SELECT id FROM muscle_groups WHERE name = 'Lats'), 'beginner', 'Grip the bar wide, pull the chin over the bar, control the way down. Work toward this once the assisted machine no longer needs any assist weight.', 'Pullups', 0),

      ('Seated cable row', 'strength', (SELECT id FROM equipment WHERE name = 'Cable machine'), (SELECT id FROM muscle_groups WHERE name = 'Back'), 'beginner', 'Pull the handle to the stomach, squeeze shoulder blades together, control the return.', 'Seated_Cable_Rows', 2.5),
      ('Barbell row', 'strength', (SELECT id FROM equipment WHERE name = 'Barbell'), (SELECT id FROM muscle_groups WHERE name = 'Back'), 'beginner', 'Hinge forward with a flat back, pull the bar to the lower ribs, control the return.', 'Bent_Over_Barbell_Row', 2.5),
      ('Dumbbell row', 'strength', (SELECT id FROM equipment WHERE name = 'Dumbbell'), (SELECT id FROM muscle_groups WHERE name = 'Back'), 'beginner', 'One hand and knee on a bench, pull the dumbbell to the hip, control the return.', 'One-Arm_Dumbbell_Row', 2.5),

      ('Barbell curl', 'strength', (SELECT id FROM equipment WHERE name = 'Barbell'), (SELECT id FROM muscle_groups WHERE name = 'Biceps'), 'beginner', 'Elbows tucked at your sides, curl the bar up, control the return.', 'Barbell_Curl', 2.5),
      ('Dumbbell curl', 'strength', (SELECT id FROM equipment WHERE name = 'Dumbbell'), (SELECT id FROM muscle_groups WHERE name = 'Biceps'), 'beginner', 'Curl both dumbbells up keeping the elbows still, control the return.', 'Seated_Dumbbell_Curl', 1.0),

      ('Plank', 'strength', NULL, (SELECT id FROM muscle_groups WHERE name = 'Core'), 'beginner', 'Hold a straight line from shoulders to ankles on forearms and toes. Target reps below are seconds held.', 'Plank', 0),
      ('Dead bug', 'strength', NULL, (SELECT id FROM muscle_groups WHERE name = 'Core'), 'beginner', 'Lying on your back, lower opposite arm and leg toward the floor, keep the low back flat. Target reps below are seconds held per side.', 'Dead_Bug', 0),
      ('Seated crunch machine', 'strength', (SELECT id FROM equipment WHERE name = 'Crunch machine'), (SELECT id FROM muscle_groups WHERE name = 'Core'), 'beginner', 'Set the pad at chest height, curl forward against the resistance, control the return.', 'Ab_Crunch_Machine', 2.5),
      ('Cable crunch', 'strength', (SELECT id FROM equipment WHERE name = 'Cable machine'), (SELECT id FROM muscle_groups WHERE name = 'Core'), 'beginner', 'Kneel below the cable, curl the torso down bringing elbows toward the knees, control the return.', 'Cable_Crunch', 2.5),
      ('Hanging leg raise', 'strength', (SELECT id FROM equipment WHERE name = 'Pull-up bar'), (SELECT id FROM muscle_groups WHERE name = 'Core'), 'beginner', 'Hang from the bar, raise the legs to hip height or higher, control the return.', 'Hanging_Leg_Raise', 0),

      ('Barbell lunge', 'strength', (SELECT id FROM equipment WHERE name = 'Barbell'), (SELECT id FROM muscle_groups WHERE name = 'Quads'), 'beginner', 'Bar on upper back, step forward into a lunge, drive back to standing, alternate legs.', 'Barbell_Lunge', 2.5),
      ('Bodyweight squat', 'strength', NULL, (SELECT id FROM muscle_groups WHERE name = 'Quads'), 'beginner', 'Feet shoulder width, sit hips back and down, drive up through the heels.', 'Bodyweight_Squat', 0),
      ('Front squat', 'strength', (SELECT id FROM equipment WHERE name = 'Barbell'), (SELECT id FROM muscle_groups WHERE name = 'Quads'), 'beginner', 'Bar racked across the front of the shoulders, squat down keeping the torso upright, drive back up.', 'Front_Squat_Clean_Grip', 5.0),
      ('Smith machine squat', 'strength', (SELECT id FROM equipment WHERE name = 'Smith machine'), (SELECT id FROM muscle_groups WHERE name = 'Quads'), 'beginner', 'Bar on upper back in the fixed-track machine, squat down, drive back up.', 'Smith_Machine_Squat', 5.0),
      ('Barbell walking lunge', 'strength', (SELECT id FROM equipment WHERE name = 'Barbell'), (SELECT id FROM muscle_groups WHERE name = 'Quads'), 'beginner', 'Bar on upper back, step forward into a lunge and continue walking forward, alternating legs.', 'Barbell_Walking_Lunge', 2.5),

      ('Seated leg curl', 'strength', (SELECT id FROM equipment WHERE name = 'Leg curl machine'), (SELECT id FROM muscle_groups WHERE name = 'Hamstrings'), 'beginner', 'Sit with the pad against the shins, curl the legs down and back, control the return.', 'Seated_Leg_Curl', 5.0),
      ('Standing leg curl', 'strength', (SELECT id FROM equipment WHERE name = 'Leg curl machine'), (SELECT id FROM muscle_groups WHERE name = 'Hamstrings'), 'beginner', 'Stand facing the machine, curl one heel toward the glute, control the return.', 'Standing_Leg_Curl', 5.0),
      ('Stiff-legged dumbbell deadlift', 'strength', (SELECT id FROM equipment WHERE name = 'Dumbbell'), (SELECT id FROM muscle_groups WHERE name = 'Hamstrings'), 'beginner', 'Legs nearly straight, hinge at the hips lowering the dumbbells along the legs, drive hips forward to stand.', 'Stiff-Legged_Dumbbell_Deadlift', 2.5),
      ('Glute ham raise', 'strength', NULL, (SELECT id FROM muscle_groups WHERE name = 'Hamstrings'), 'beginner', 'Anchor the ankles, lower the torso forward under control, curl back up using the hamstrings.', 'Natural_Glute_Ham_Raise', 0),

      ('Glute bridge', 'strength', NULL, (SELECT id FROM muscle_groups WHERE name = 'Glutes'), 'beginner', 'Lying on your back, knees bent, drive the hips up, squeeze the glutes at the top.', 'Butt_Lift_Bridge', 0),
      ('Single leg glute bridge', 'strength', NULL, (SELECT id FROM muscle_groups WHERE name = 'Glutes'), 'beginner', 'Same as a glute bridge with one foot lifted, driving through the planted heel.', 'Single_Leg_Glute_Bridge', 0),
      ('Cable pull through', 'strength', (SELECT id FROM equipment WHERE name = 'Cable machine'), (SELECT id FROM muscle_groups WHERE name = 'Glutes'), 'beginner', 'Facing away from the low cable, hinge forward and pull the rope through between the legs, drive hips forward to stand.', 'Pull_Through', 2.5),

      ('Calf press on leg press', 'strength', (SELECT id FROM equipment WHERE name = 'Leg press machine'), (SELECT id FROM muscle_groups WHERE name = 'Calves'), 'beginner', 'Feet low on the platform, toes only, press through the balls of the feet, lower under control.', 'Calf_Press_On_The_Leg_Press_Machine', 10.0),
      ('Standing barbell calf raise', 'strength', (SELECT id FROM equipment WHERE name = 'Barbell'), (SELECT id FROM muscle_groups WHERE name = 'Calves'), 'beginner', 'Bar on upper back, rise onto the toes, pause, lower under control.', 'Standing_Barbell_Calf_Raise', 5.0),
      ('Standing dumbbell calf raise', 'strength', (SELECT id FROM equipment WHERE name = 'Dumbbell'), (SELECT id FROM muscle_groups WHERE name = 'Calves'), 'beginner', 'Hold dumbbells at your sides, rise onto the toes, pause, lower under control.', 'Standing_Dumbbell_Calf_Raise', 2.5),

      ('Barbell incline bench press', 'strength', (SELECT id FROM equipment WHERE name = 'Barbell'), (SELECT id FROM muscle_groups WHERE name = 'Chest'), 'beginner', 'Bench set to an incline, lower the bar to the upper chest, press back up to full extension.', 'Barbell_Incline_Bench_Press_-_Medium_Grip', 2.5),
      ('Decline barbell bench press', 'strength', (SELECT id FROM equipment WHERE name = 'Barbell'), (SELECT id FROM muscle_groups WHERE name = 'Chest'), 'beginner', 'Bench set to a decline, lower the bar to the lower chest, press back up to full extension.', 'Decline_Barbell_Bench_Press', 2.5),
      ('Dumbbell flyes', 'strength', (SELECT id FROM equipment WHERE name = 'Dumbbell'), (SELECT id FROM muscle_groups WHERE name = 'Chest'), 'beginner', 'Lie on the bench, arms slightly bent, lower the dumbbells out to the sides, bring them back together over the chest.', 'Dumbbell_Flyes', 1.0),
      ('Cable crossover', 'strength', (SELECT id FROM equipment WHERE name = 'Cable machine'), (SELECT id FROM muscle_groups WHERE name = 'Chest'), 'beginner', 'Standing between two high pulleys, pull both handles down and together in front of the chest.', 'Cable_Crossover', 2.5),
      ('Machine bench press', 'strength', (SELECT id FROM equipment WHERE name = 'Machine'), (SELECT id FROM muscle_groups WHERE name = 'Chest'), 'beginner', 'Sit at the machine, press the handles forward to full extension, control the return.', 'Machine_Bench_Press', 5.0),

      ('Arnold press', 'strength', (SELECT id FROM equipment WHERE name = 'Dumbbell'), (SELECT id FROM muscle_groups WHERE name = 'Shoulders'), 'beginner', 'Start with palms facing you at shoulder height, press up while rotating palms forward, reverse on the way down.', 'Arnold_Dumbbell_Press', 2.5),
      ('Front dumbbell raise', 'strength', (SELECT id FROM equipment WHERE name = 'Dumbbell'), (SELECT id FROM muscle_groups WHERE name = 'Shoulders'), 'beginner', 'Raise both dumbbells straight out in front to shoulder height, control the return.', 'Front_Dumbbell_Raise', 1.0),
      ('Face pull', 'strength', (SELECT id FROM equipment WHERE name = 'Cable machine'), (SELECT id FROM muscle_groups WHERE name = 'Shoulders'), 'beginner', 'Rope attachment at head height, pull toward the face with elbows high, squeeze the shoulder blades.', 'Face_Pull', 2.5),
      ('Seated barbell shoulder press', 'strength', (SELECT id FROM equipment WHERE name = 'Barbell'), (SELECT id FROM muscle_groups WHERE name = 'Shoulders'), 'beginner', 'Sit with back supported, press the bar from shoulders to full extension overhead.', 'Seated_Barbell_Military_Press', 2.5),
      ('Reverse flyes', 'strength', (SELECT id FROM equipment WHERE name = 'Dumbbell'), (SELECT id FROM muscle_groups WHERE name = 'Shoulders'), 'beginner', 'Hinge forward, raise both dumbbells out to the sides, squeeze the shoulder blades together.', 'Reverse_Flyes', 1.0),

      ('Close-grip bench press', 'strength', (SELECT id FROM equipment WHERE name = 'Barbell'), (SELECT id FROM muscle_groups WHERE name = 'Triceps'), 'beginner', 'Hands closer than shoulder width, lower the bar to the chest, press back up to full extension.', 'Close-Grip_Barbell_Bench_Press', 2.5),
      ('EZ-bar skullcrusher', 'strength', (SELECT id FROM equipment WHERE name = 'EZ curl bar'), (SELECT id FROM muscle_groups WHERE name = 'Triceps'), 'beginner', 'Lying on the bench, lower the bar toward the forehead by bending the elbows, extend back up.', 'EZ-Bar_Skullcrusher', 2.5),
      ('Dumbbell triceps extension', 'strength', (SELECT id FROM equipment WHERE name = 'Dumbbell'), (SELECT id FROM muscle_groups WHERE name = 'Triceps'), 'beginner', 'Raise one dumbbell overhead, lower it behind the head by bending the elbow, extend back up.', 'Dumbbell_One-Arm_Triceps_Extension', 1.0),
      ('Rope triceps pushdown', 'strength', (SELECT id FROM equipment WHERE name = 'Cable machine'), (SELECT id FROM muscle_groups WHERE name = 'Triceps'), 'beginner', 'Rope attachment, push down and apart at the bottom, control the return.', 'Triceps_Pushdown_-_Rope_Attachment', 2.5),
      ('Bench dip', 'strength', NULL, (SELECT id FROM muscle_groups WHERE name = 'Triceps'), 'beginner', 'Hands on a bench behind you, lower the body by bending the elbows, press back up.', 'Bench_Dips', 0),

      ('Close-grip lat pulldown', 'strength', (SELECT id FROM equipment WHERE name = 'Cable machine'), (SELECT id FROM muscle_groups WHERE name = 'Lats'), 'beginner', 'Close, neutral grip handle, pull down to the upper chest, control the return.', 'Close-Grip_Front_Lat_Pulldown', 2.5),
      ('One arm lat pulldown', 'strength', (SELECT id FROM equipment WHERE name = 'Cable machine'), (SELECT id FROM muscle_groups WHERE name = 'Lats'), 'beginner', 'Single handle attachment, pull down and back with one arm, control the return.', 'One_Arm_Lat_Pulldown', 2.5),
      ('Chin-up', 'strength', (SELECT id FROM equipment WHERE name = 'Pull-up bar'), (SELECT id FROM muscle_groups WHERE name = 'Lats'), 'beginner', 'Underhand grip, pull the chin over the bar, control the way down.', 'Chin-Up', 0),
      ('Straight-arm pulldown', 'strength', (SELECT id FROM equipment WHERE name = 'Cable machine'), (SELECT id FROM muscle_groups WHERE name = 'Lats'), 'beginner', 'Arms straight, pull the bar down toward the thighs using the lats, control the return.', 'Straight-Arm_Pulldown', 2.5),

      ('T-bar row', 'strength', (SELECT id FROM equipment WHERE name = 'Machine'), (SELECT id FROM muscle_groups WHERE name = 'Back'), 'beginner', 'Straddle the bar, hinge forward, pull the handle to the chest, control the return.', 'T-Bar_Row_with_Handle', 5.0),
      ('Smith machine bent over row', 'strength', (SELECT id FROM equipment WHERE name = 'Smith machine'), (SELECT id FROM muscle_groups WHERE name = 'Back'), 'beginner', 'Hinge forward under the fixed-track bar, row it to the stomach, control the return.', 'Smith_Machine_Bent_Over_Row', 5.0),
      ('Incline bench pull', 'strength', (SELECT id FROM equipment WHERE name = 'Barbell'), (SELECT id FROM muscle_groups WHERE name = 'Back'), 'beginner', 'Lie face down on an incline bench, row the bar to the chest, control the return.', 'Incline_Bench_Pull', 2.5),
      ('Seated one-arm cable row', 'strength', (SELECT id FROM equipment WHERE name = 'Cable machine'), (SELECT id FROM muscle_groups WHERE name = 'Back'), 'beginner', 'Seated at a low pulley, pull the handle to the hip with one arm, control the return.', 'Seated_One-arm_Cable_Pulley_Rows', 2.5),

      ('Hammer curl', 'strength', (SELECT id FROM equipment WHERE name = 'Dumbbell'), (SELECT id FROM muscle_groups WHERE name = 'Biceps'), 'beginner', 'Neutral grip, curl both dumbbells up keeping the elbows still, control the return.', 'Hammer_Curls', 1.0),
      ('EZ-bar curl', 'strength', (SELECT id FROM equipment WHERE name = 'EZ curl bar'), (SELECT id FROM muscle_groups WHERE name = 'Biceps'), 'beginner', 'Curl the angled bar up keeping the elbows tucked, control the return.', 'EZ-Bar_Curl', 2.5),
      ('Preacher curl', 'strength', (SELECT id FROM equipment WHERE name = 'Barbell'), (SELECT id FROM muscle_groups WHERE name = 'Biceps'), 'beginner', 'Arms braced on the preacher pad, curl the bar up, control the return.', 'Preacher_Curl', 2.5),
      ('Concentration curl', 'strength', (SELECT id FROM equipment WHERE name = 'Dumbbell'), (SELECT id FROM muscle_groups WHERE name = 'Biceps'), 'beginner', 'Seated, elbow braced against the inner thigh, curl the dumbbell up, control the return.', 'Concentration_Curls', 1.0),
      ('Cable preacher curl', 'strength', (SELECT id FROM equipment WHERE name = 'Cable machine'), (SELECT id FROM muscle_groups WHERE name = 'Biceps'), 'beginner', 'Arms braced on the preacher pad, curl the low cable handle up, control the return.', 'Cable_Preacher_Curl', 2.5),

      ('Russian twist', 'strength', NULL, (SELECT id FROM muscle_groups WHERE name = 'Core'), 'beginner', 'Seated, lean back slightly, rotate the torso side to side.', 'Russian_Twist', 0),
      ('Sit-up', 'strength', NULL, (SELECT id FROM muscle_groups WHERE name = 'Core'), 'beginner', 'Feet anchored, curl the torso all the way up to the knees, lower back down under control.', 'Sit-Up', 0),
      ('Reverse crunch', 'strength', NULL, (SELECT id FROM muscle_groups WHERE name = 'Core'), 'beginner', 'Lying on your back, curl the hips up toward the chest, lower under control.', 'Reverse_Crunch', 0),
      ('Bicycle crunch', 'strength', NULL, (SELECT id FROM muscle_groups WHERE name = 'Core'), 'beginner', 'Lying on your back, alternate bringing opposite elbow to opposite knee in a pedaling motion.', 'Air_Bike', 0),
      ('Side plank', 'strength', NULL, (SELECT id FROM muscle_groups WHERE name = 'Core'), 'beginner', 'Prop up on one forearm, body in a straight line, hips lifted, hold.', 'Side_Bridge', 0);

    INSERT INTO workout_templates (name, goal, notes) VALUES
      ('Workout A', 'recomposition', 'Full body, alternate with Workout B, 3x per week.'),
      ('Workout B', 'recomposition', 'Full body, alternate with Workout A, 3x per week.');

    INSERT INTO workout_template_exercises (template_id, exercise_id, target_sets, target_reps_min, target_reps_max, order_index) VALUES
      ((SELECT id FROM workout_templates WHERE name = 'Workout A'), (SELECT id FROM exercises WHERE name = 'Barbell back squat'), 3, 8, 10, 1),
      ((SELECT id FROM workout_templates WHERE name = 'Workout A'), (SELECT id FROM exercises WHERE name = 'Barbell bench press'), 3, 8, 10, 2),
      ((SELECT id FROM workout_templates WHERE name = 'Workout A'), (SELECT id FROM exercises WHERE name = 'Lat pulldown'), 3, 8, 10, 3),
      ((SELECT id FROM workout_templates WHERE name = 'Workout A'), (SELECT id FROM exercises WHERE name = 'Plank'), 3, 30, 45, 4),
      ((SELECT id FROM workout_templates WHERE name = 'Workout B'), (SELECT id FROM exercises WHERE name = 'Barbell deadlift'), 3, 5, 8, 1),
      ((SELECT id FROM workout_templates WHERE name = 'Workout B'), (SELECT id FROM exercises WHERE name = 'Overhead press'), 3, 8, 10, 2),
      ((SELECT id FROM workout_templates WHERE name = 'Workout B'), (SELECT id FROM exercises WHERE name = 'Seated cable row'), 3, 8, 10, 3),
      ((SELECT id FROM workout_templates WHERE name = 'Workout B'), (SELECT id FROM exercises WHERE name = 'Seated crunch machine'), 3, 12, 15, 4);
    """

    // MARK: - Generic query helpers

    @discardableResult
    func execute(_ sql: String, bind: ((OpaquePointer?) -> Void)? = nil) -> Bool {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            print("⚠️ Prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return false
        }
        bind?(statement)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    func query(_ sql: String, bind: ((OpaquePointer?) -> Void)? = nil,
               map: (OpaquePointer?) -> Void) {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            print("⚠️ Prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        bind?(statement)
        while sqlite3_step(statement) == SQLITE_ROW {
            map(statement)
        }
    }

    var lastInsertId: Int {
        Int(sqlite3_last_insert_rowid(db))
    }
}

// MARK: - workout_sets — persistence for logged sets
extension Database {
    /// Inserts one completed set (or warmup) and returns its row id.
    /// Called from the session flow's onSetLogged handler, once per tap
    /// of "Done" in LogSetView — so a crash mid-workout loses at most
    /// the set in progress, never the ones already logged.
    @discardableResult
    func insertWorkoutSet(sessionId: Int, exerciseId: Int, setNumber: Int,
                           reps: Int, weightKg: Double, rpe: Double?,
                           isWarmup: Bool, restSeconds: Int?) -> Int {
        execute("""
            INSERT INTO workout_sets
                (session_id, exercise_id, set_number, reps, weight_kg, rpe, is_warmup, rest_seconds)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """) { statement in
            sqlite3_bind_int(statement, 1, Int32(sessionId))
            sqlite3_bind_int(statement, 2, Int32(exerciseId))
            sqlite3_bind_int(statement, 3, Int32(setNumber))
            sqlite3_bind_int(statement, 4, Int32(reps))
            sqlite3_bind_double(statement, 5, weightKg)
            if let rpe {
                sqlite3_bind_double(statement, 6, rpe)
            } else {
                sqlite3_bind_null(statement, 6)
            }
            sqlite3_bind_int(statement, 7, isWarmup ? 1 : 0)
            if let restSeconds {
                sqlite3_bind_int(statement, 8, Int32(restSeconds))
            } else {
                sqlite3_bind_null(statement, 8)
            }
        }
        return lastInsertId
    }

    /// Every past working set for this exercise, grouped by session and
    /// ordered most-recent-session-first — the raw material for
    /// ProgressionEngine's add/repeat/deload decision. Sets from the
    /// same session are always logged in one contiguous run (only one
    /// session is ever active at a time), so a simple "same id as last
    /// row" check is enough to group them correctly.
    func recentSessionPerformance(exerciseId: Int, limit: Int = 5) -> [SessionPerformance] {
        struct Row { let sessionId: Int; let weightKg: Double; let reps: Int }
        var rows: [Row] = []
        query("""
            SELECT session_id, weight_kg, reps
            FROM workout_sets
            WHERE exercise_id = ? AND is_warmup = 0
            ORDER BY completed_at DESC
            LIMIT 60
            """, bind: { statement in
            sqlite3_bind_int(statement, 1, Int32(exerciseId))
        }) { statement in
            rows.append(Row(
                sessionId: Int(sqlite3_column_int(statement, 0)),
                weightKg: sqlite3_column_double(statement, 1),
                reps: Int(sqlite3_column_int(statement, 2))
            ))
        }

        var sessions: [SessionPerformance] = []
        var currentSessionId: Int?
        for row in rows {
            if row.sessionId == currentSessionId, var last = sessions.popLast() {
                last.reps.append(row.reps)
                sessions.append(last)
            } else {
                sessions.append(SessionPerformance(weightKg: row.weightKg, reps: [row.reps]))
                currentSessionId = row.sessionId
            }
        }
        return Array(sessions.prefix(limit))
    }

    /// Suggested weight for the next set of this exercise, per the
    /// double-progression rule. Returns nil on the very first time it's
    /// ever performed — that's the session-1 calibration case, where the
    /// weight comes from the person via the steppers, not a suggestion.
    func suggestedWeightKg(exerciseId: Int, targetReps: ClosedRange<Int>, incrementKg: Double) -> Double? {
        let history = recentSessionPerformance(exerciseId: exerciseId)
        return ProgressionEngine.suggestedWeightKg(history: history, targetReps: targetReps, incrementKg: incrementKg)
    }

    /// Exercises for a template, in program order, joined with their
    /// target set/rep ranges — what the session flow walks through.
    func templateExercises(templateId: Int) -> [SessionExercise] {
        var results: [SessionExercise] = []
        query("""
            SELECT e.id, e.name, te.target_sets, te.target_reps_min, te.target_reps_max, e.increment_kg, e.demo_asset_id
            FROM workout_template_exercises te
            JOIN exercises e ON e.id = te.exercise_id
            WHERE te.template_id = ?
            ORDER BY te.order_index
            """, bind: { statement in
            sqlite3_bind_int(statement, 1, Int32(templateId))
        }) { statement in
            results.append(SessionExercise(
                id: Int(sqlite3_column_int(statement, 0)),
                name: String(cString: sqlite3_column_text(statement, 1)),
                targetSets: Int(sqlite3_column_int(statement, 2)),
                targetRepsMin: Int(sqlite3_column_int(statement, 3)),
                targetRepsMax: Int(sqlite3_column_int(statement, 4)),
                incrementKg: sqlite3_column_double(statement, 5),
                demoAssetId: sqlite3_column_text(statement, 6).map { String(cString: $0) }
            ))
        }
        return results
    }

    /// Marks a session finished and optionally records its HealthKit
    /// workout UUID once HealthKitManager.saveWorkout returns one.
    func endSession(sessionId: Int, endTime: Date, healthKitUUID: String?) {
        execute("UPDATE workout_sessions SET end_time = ?, healthkit_uuid = ? WHERE id = ?") { statement in
            sqlite3_bind_text(statement, 1, ISO8601DateFormatter().string(from: endTime), -1, SQLITE_TRANSIENT)
            if let healthKitUUID {
                sqlite3_bind_text(statement, 2, healthKitUUID, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 2)
            }
            sqlite3_bind_int(statement, 3, Int32(sessionId))
        }
    }
}

// MARK: - body_measurements — body weight entered in-app
extension Database {
    /// Logs a new weight entry, sourced from GymApp rather than a scale
    /// or the Health app directly.
    func insertBodyWeight(kg: Double, at date: Date = Date()) {
        let success = execute("INSERT INTO body_measurements (recorded_at, weight_kg, source) VALUES (?, ?, 'manual')") { statement in
            sqlite3_bind_text(statement, 1, ISO8601DateFormatter().string(from: date), -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 2, kg)
        }
        Self.log(success ? "✅ Body weight saved (\(kg)kg)" : "❌ Body weight insert failed")
    }

    /// Most recent weight on file, whichever source logged it — used to
    /// pre-fill the weight entry sheet and to feed the calorie estimate.
    func latestBodyWeightKg() -> Double? {
        var result: Double?
        query("SELECT weight_kg FROM body_measurements WHERE weight_kg IS NOT NULL ORDER BY recorded_at DESC LIMIT 1") { statement in
            result = sqlite3_column_double(statement, 0)
        }
        return result
    }
}

// MARK: - Exercise substitution
extension Database {
    /// The primary muscle group for an exercise — shared by
    /// alternateExercises and by photo-ID's "same slot" substitution.
    func muscleGroupId(forExerciseId exerciseId: Int) -> Int? {
        var muscleId: Int?
        query("SELECT primary_muscle_id FROM exercises WHERE id = ?", bind: { statement in
            sqlite3_bind_int(statement, 1, Int32(exerciseId))
        }) { statement in
            if sqlite3_column_type(statement, 0) != SQLITE_NULL {
                muscleId = Int(sqlite3_column_int(statement, 0))
            }
        }
        return muscleId
    }

    /// Other exercises hitting the same primary muscle group — what the
    /// "swap" option in the preview screen offers when a machine isn't
    /// available.
    func alternateExercises(excluding exerciseId: Int) -> [(id: Int, name: String, incrementKg: Double, demoAssetId: String?)] {
        guard let muscleId = muscleGroupId(forExerciseId: exerciseId) else { return [] }

        var results: [(id: Int, name: String, incrementKg: Double, demoAssetId: String?)] = []
        query("SELECT id, name, increment_kg, demo_asset_id FROM exercises WHERE primary_muscle_id = ? AND id != ?", bind: { statement in
            sqlite3_bind_int(statement, 1, Int32(muscleId))
            sqlite3_bind_int(statement, 2, Int32(exerciseId))
        }) { statement in
            results.append((
                id: Int(sqlite3_column_int(statement, 0)),
                name: String(cString: sqlite3_column_text(statement, 1)),
                incrementKg: sqlite3_column_double(statement, 2),
                demoAssetId: sqlite3_column_text(statement, 3).map { String(cString: $0) }
            ))
        }
        return results
    }
}

// MARK: - Workout history — for suggesting the next A/B alternation
extension Database {
    /// The template used in whichever completed session finished most
    /// recently — the basis for "you did A last, so B is next".
    /// Ignores sessions that were started but never finished.
    func mostRecentCompletedSessionTemplateId() -> Int? {
        var templateId: Int?
        query("SELECT template_id FROM workout_sessions WHERE end_time IS NOT NULL ORDER BY end_time DESC LIMIT 1") { statement in
            if sqlite3_column_type(statement, 0) != SQLITE_NULL {
                templateId = Int(sqlite3_column_int(statement, 0))
            }
        }
        return templateId
    }

    /// Total number of finished workouts, ever — shown on the home
    /// screen. Only counts sessions that actually got an end_time.
    func totalCompletedSessionsCount() -> Int {
        var count = 0
        query("SELECT COUNT(*) FROM workout_sessions WHERE end_time IS NOT NULL") { statement in
            count = Int(sqlite3_column_int(statement, 0))
        }
        return count
    }
}

// MARK: - Photo-based equipment identification
extension Database {
    /// Saves a newly photo-identified machine as its own equipment row,
    /// distinct from anything hand-seeded — identified_via_photo marks
    /// where it came from.
    @discardableResult
    func insertIdentifiedEquipment(name: String) -> Int {
        execute("INSERT INTO equipment (name, category, identified_via_photo) VALUES (?, 'machine', 1)") { statement in
            sqlite3_bind_text(statement, 1, name, -1, SQLITE_TRANSIENT)
        }
        return lastInsertId
    }

    /// Creates the exercise entry for a photo-identified machine, in
    /// the same muscle group as whatever exercise it's replacing, so it
    /// slots into the swap picker like any other alternative from then on.
    @discardableResult
    func insertCustomExercise(name: String, muscleGroupId: Int, equipmentId: Int, instructions: String, incrementKg: Double) -> Int {
        execute("""
            INSERT INTO exercises (name, exercise_type, equipment_id, primary_muscle_id, difficulty, instructions, increment_kg, is_custom)
            VALUES (?, 'strength', ?, ?, 'beginner', ?, ?, 1)
            """) { statement in
            sqlite3_bind_text(statement, 1, name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 2, Int32(equipmentId))
            sqlite3_bind_int(statement, 3, Int32(muscleGroupId))
            sqlite3_bind_text(statement, 4, instructions, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 5, incrementKg)
        }
        return lastInsertId
    }

    /// Keeps a record of what the vision model actually said, in case a
    /// future identification of the same machine needs comparing against it.
    func logMachineRecognition(equipmentId: Int, rawResponse: String) {
        execute("INSERT INTO machine_recognition_log (equipment_id, raw_llm_response) VALUES (?, ?)") { statement in
            sqlite3_bind_int(statement, 1, Int32(equipmentId))
            sqlite3_bind_text(statement, 2, rawResponse, -1, SQLITE_TRANSIENT)
        }
    }
}
