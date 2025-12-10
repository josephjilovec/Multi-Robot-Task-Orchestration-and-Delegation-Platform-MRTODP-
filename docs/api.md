# MRTODP API Documentation

## Overview

The MRTODP API provides endpoints for task orchestration and skills marketplace management.

## Task Management API

### POST /api/tasks
Create a new task.

**Request Body:**
```json
{
  "id": "task_001",
  "command": "weld_component",
  "robotId": "KUKA",
  "parameters": [100.0, 10.0, 20.0, 30.0, 1.0]
}
```

**Response:**
```json
{
  "id": "task_001",
  "status": "assigned",
  "robot_id": "KUKA"
}
```

### GET /api/tasks
Get all tasks.

**Response:**
```json
{
  "tasks": [
    {
      "id": "task_001",
      "type": "weld_component",
      "robot_id": "KUKA",
      "status": "completed"
    }
  ]
}
```

## Skills Marketplace API

### POST /api/skills
Upload a new skill.

**Request Body:**
```json
{
  "id": "skill_001",
  "name": "Navigation Skill",
  "robotType": "KUKA",
  "code": "PTP {...}",
  "metadata": {}
}
```

### GET /api/skills/:id
Download a skill by ID.

### GET /api/skills/usage
Get skill usage statistics.

## Authentication

All endpoints require authentication via JWT token in the Authorization header:
```
Authorization: Bearer <token>
```

