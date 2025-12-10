-- PostgreSQL schema for MRTODP skills marketplace

CREATE TABLE IF NOT EXISTS skills (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    task_type VARCHAR(255) NOT NULL,
    description TEXT,
    robot_id VARCHAR(255) NOT NULL,
    code TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_skills_task_type ON skills(task_type);
CREATE INDEX IF NOT EXISTS idx_skills_robot_id ON skills(robot_id);

