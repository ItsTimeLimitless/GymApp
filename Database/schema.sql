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
