-- SQLite schema for MRTODP task storage

CREATE TABLE IF NOT EXISTS tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_type TEXT NOT NULL,
    robot_id TEXT,
    status TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS robot_capabilities (
    robot_id TEXT NOT NULL,
    capability TEXT NOT NULL,
    strength INTEGER NOT NULL,
    PRIMARY KEY (robot_id, capability)
);

CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_robot_id ON tasks(robot_id);
CREATE INDEX IF NOT EXISTS idx_robot_capabilities_robot_id ON robot_capabilities(robot_id);

