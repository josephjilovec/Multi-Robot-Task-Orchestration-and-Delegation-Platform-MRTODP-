MRTODP API Documentation
Overview
This document details the public APIs of the Multi-Robot Task Orchestration and Delegation Platform (MRTODP), covering key functions and endpoints across backend components. These APIs facilitate task orchestration, skill management, and robot interactions for advanced users (e.g., robotics engineers, AI developers). The APIs are implemented in C++, Python, Common Lisp, Scala, and Elixir, integrating with the system architecture described in architecture.md. Each section includes function signatures, endpoints, inputs, outputs, usage examples, and error conditions, presented in tables and code blocks for clarity.
1. C++ Task Orchestrator (backend/cpp/task_manager/)
The C++ task orchestrator, implemented in orchestrator.cpp, manages task delegation and robot capability matching, interfacing with ROS and SQLite. See architecture.md for details.



Function
Signature
Inputs
Outputs
Description
Error Conditions



delegateTask
bool delegateTask(const Task& task)
Task: Struct with id (string), command (string), robotId (string), parameters (vector)
bool: True if task is delegated successfully
Delegates a task to a robot via ROS after validating capabilities with SQLite
- std::invalid_argument: Empty id or command- std::runtime_error: Invalid robot ID, unsupported command, ROS failure, SQLite failure


matchRobotToTask
bool matchRobotToTask(const std::string& command, std::string& robotId)
command: Task command (string)robotId: Output robot ID (string)
bool: True if a matching robot is found
Matches a task command to a robot with the required capability
- std::runtime_error: No robot supports the command


Example
#include "orchestrator.hpp"

Orchestrator orchestrator(&rosClient, &sqliteDB);
Task task{"TASK_1", "weld_component", "KUKA_1", {100.0, 10.0, 20.0, 30.0, 1.0}};
try {
    bool success = orchestrator.delegateTask(task);
    std::cout << "Task delegated: " << (success ? "Success" : "Failure") << std::endl;
} catch (const std::exception& e) {
    std::cerr << "Error: " << e.what() << std::endl;
}

std::string robotId;
if (orchestrator.matchRobotToTask("weld_component", robotId)) {
    std::cout << "Matched robot: " << robotId << std::endl;
}

Tests

See tests/cpp/test_orchestrator.cpp for unit tests covering delegateTask and matchRobotToTask.

2. Python AI Engine (backend/python/ai_engine/)
The Python AI engine, implemented in delegator.py, uses TensorFlow for task suitability prediction and gRPC for orchestrator communication. See architecture.md for details.



Function
Signature
Inputs
Outputs
Description
Error Conditions



predict_task_suitability
predict_task_suitability(task: Task) -> list[float]
task: Task dataclass with id (str), command (str), robot_id (str), parameters (list[float])
list[float]: Suitability scores for robots
Predicts robot suitability using a TensorFlow model
- ValueError: Invalid or empty parameters (length ≠ 5)


assign_robot
assign_robot(task: Task) -> str
task: Task dataclass
str: Assigned robot ID
Assigns a robot based on suitability scores and delegates via gRPC
- ValueError: Empty id or command- RuntimeError: gRPC delegation failure


Example
from backend.python.ai_engine.delegator import Delegator, Task

delegator = Delegator(model, grpc_client)
task = Task(id="TASK_1", command="weld_component", robot_id="", parameters=[100.0, 10.0, 20.0, 30.0, 1.0])
try:
    scores = delegator.predict_task_suitability(task)
    print(f"Suitability scores: {scores}")
    robot_id = delegator.assign_robot(task)
    print(f"Assigned robot: {robot_id}")
except ValueError as e:
    print(f"Error: {e}")
except RuntimeError as e:
    print(f"Error: {e}")

Tests

See tests/python/test_delegator.py for unit tests covering predict_task_suitability and assign_robot.

3. Common Lisp Planner (backend/lisp/planner.lisp)
The Common Lisp planner decomposes tasks into subtasks and generates symbolic instructions, interfacing with SQLite and Python. See architecture.md for details.



Function
Signature
Inputs
Outputs
Description
Error Conditions



decompose-task
(decompose-task planner task-id command parameters)
planner: planner instancetask-id: Stringcommand: Stringparameters: List of floats
List of plists: Subtasks with :id, :command, :parameters
Decomposes a task into subtasks and stores them in SQLite
- error: Empty task-id, command, or parameters- error: Invalid parameters (length ≠ 5)- error: Unsupported command


generate-instructions
(generate-instructions planner task-id)
planner: planner instancetask-id: String
List of plists: Instructions with :subtask-id, :robot-id, :command, :parameters
Generates symbolic instructions by assigning subtasks to robots
- error: Task not found- error: Subtask assignment failure


Example
(load "backend/lisp/planner.lisp")
(defvar planner (make-instance 'planner :db (make-instance 'sqlite-db) :delegator (make-instance 'python-delegator)))
(handler-case
    (let ((subtasks (decompose-task planner "TASK_1" "weld_component" '(100.0 10.0 20.0 30.0 1.0))))
      (format t "Subtasks: ~A~%" subtasks)
      (let ((instructions (generate-instructions planner "TASK_1")))
        (format t "Instructions: ~A~%" instructions)))
  (error (e)
    (format t "Error: ~A~%" e)))

Tests

See tests/lisp/test_planner.lisp for unit tests covering decompose-task and generate-instructions.

4. Scala Marketplace API (backend/scala/marketplace/)
The Scala marketplace API, implemented in api.scala, provides RESTful endpoints for skill management using Akka HTTP and PostgreSQL. See architecture.md for details.



Endpoint
Method
Inputs
Outputs
Description
Error Conditions



/api/skills
GET
None
JSON: List of skills {id: String, name: String, robot_type: String, description: String}
Retrieves all available skills
- 500: Database connection failure


/api/skills
POST
JSON: {name: String, robot_type: String, description: String, code: String}
JSON: {id: String, status: String}
Uploads a new skill
- 400: Invalid JSON or missing fields- 500: Database failure


/api/skills/:id
GET
id: Skill ID (path parameter)
JSON: Skill details or 404
Downloads a specific skill
- 404: Skill not found- 500: Database failure


Example
# GET all skills
curl http://localhost:8080/api/skills

# POST a new skill
curl -X POST http://localhost:8080/api/skills \
  -H "Content-Type: application/json" \
  -d '{"name": "weld_component", "robot_type": "KUKA", "description": "Welds components", "code": "..."}'

# GET a specific skill
curl http://localhost:8080/api/skills/SKILL_1

Tests

See tests/scala/test_api.scala (assumed) for unit tests covering skill endpoints.

5. Elixir Marketplace Server (backend/elixir/marketplace/)
The Elixir marketplace server, implemented in server.ex, provides real-time skill management with Phoenix and Ecto. See architecture.md for details.



Endpoint
Method
Inputs
Outputs
Description
Error Conditions



/api/skills
POST
JSON: {name: String, robot_type: String, description: String, code: String}
JSON: {id: String, status: String}
Uploads and validates a new skill
- 400: Invalid JSON or missing fields- 500: Database failure


/api/skills/usage
GET
None
JSON: List of {skill_id: String, usage_count: Integer}
Provides skill usage statistics
- 500: Database connection failure


Example
# POST a new skill
curl -X POST http://localhost:4000/api/skills \
  -H "Content-Type: application/json" \
  -d '{"name": "inspect_part", "robot_type": "ABB", "description": "Inspects parts", "code": "..."}'

# GET skill usage statistics
curl http://localhost:4000/api/skills/usage

Tests

See tests/elixir/test_server.exs (assumed) for unit tests covering skill endpoints.

Integration with Frontend
The React frontend (frontend/src/components/TaskManager.js, frontend/src/components/Marketplace.js) interacts with Scala and Elixir APIs via REST and with the Python AI engine via gRPC. See architecture.md for details.
Example (Frontend)
// frontend/src/components/TaskManager.js
import axios from 'axios';

async function createTask(task) {
  try {
    const response = await axios.post('http://localhost:8080/api/tasks', {
      id: task.id,
      command: task.command,
      parameters: task.parameters
    });
    console.log('Task created:', response.data);
  } catch (error) {
    console.error('Error creating task:', error.response.data);
  }
}

Security

Authentication: All REST endpoints (api.scala, server.ex) use JWT-based authentication.
Input Validation: APIs validate inputs to prevent injection attacks.
Error Handling: Comprehensive error messages are returned (e.g., 400 for invalid inputs, 500 for server errors).

Deployment

APIs are containerized (deploy/Dockerfile) and deployed with Kubernetes (deploy/kubernetes.yml).
CI/CD pipeline (./github/workflows/ci.yml) validates API functionality.
See architecture.md for details.

Troubleshooting

C++ Errors: Check SQLite and ROS connectivity (orchestrator.cpp).
Python Errors: Verify TensorFlow and gRPC dependencies (requirements.txt).
Lisp Errors: Ensure SQLite and Python interfaces are configured (planner.lisp).
Scala/Elixir Errors: Check PostgreSQL connectivity and JWT configuration.
Frontend Errors: Validate API URLs in .env (e.g., REACT_APP_API_URL).

This API documentation ensures clarity and usability for integrating MRTODP components.
