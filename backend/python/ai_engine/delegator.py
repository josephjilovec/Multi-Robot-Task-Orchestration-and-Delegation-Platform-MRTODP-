# backend/python/ai_engine/delegator.py
# Purpose: Implements AI-driven task delegation for MRTODP using TensorFlow to predict task
# suitability for heterogeneous robots. Interfaces with backend/cpp/task_manager/orchestrator.cpp
# via gRPC for task delegation requests and queries robot capabilities from SQLite database.
# Delegates tasks to backend/python/ros_bridge/ via ROS topics. Includes robust error handling
# for model failures, unavailable robots, and database issues, ensuring reliable operation.

import os
import sqlite3
from typing import Dict, List, Optional
import tensorflow as tf
import numpy as np
import grpc
import rospy
from std_msgs.msg import String
import json
import logging

# Generated gRPC stubs (assumed from orchestrator.proto)
try:
    from . import orchestrator_pb2
    from . import orchestrator_pb2_grpc
except ImportError:
    # Fallback for development - generate stubs with: python -m grpc_tools.protoc -I. --python_out=. --grpc_python_out=. orchestrator.proto
    orchestrator_pb2 = None
    orchestrator_pb2_grpc = None

# Configure logging for debugging and error tracking
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class TaskDelegator:
    """AI-driven task delegator for MRTODP."""
    
    def __init__(self, model_path: str, db_path: str, grpc_endpoint: str, ros_topic: str):
        """Initialize the delegator with TensorFlow model, SQLite database, gRPC, and ROS."""
        # Initialize SQLite database connection first (required for capabilities)
        try:
            self.db = sqlite3.connect(db_path, check_same_thread=False)
            self.db.row_factory = sqlite3.Row
            logger.info(f"Connected to SQLite database at {db_path}")
            # Initialize database schema if needed
            self._init_database()
        except sqlite3.Error as e:
            logger.error(f"Failed to connect to SQLite database: {e}")
            raise RuntimeError(f"Database connection failed: {e}")

        # Initialize TensorFlow model (optional - can work without it)
        self.model = None
        if model_path and os.path.exists(model_path):
            try:
                self.model = tf.keras.models.load_model(model_path)
                logger.info(f"Loaded TensorFlow model from {model_path}")
            except Exception as e:
                logger.warning(f"Failed to load TensorFlow model: {e}. Continuing without model.")
        else:
            logger.warning("No model path provided or model file not found. Using rule-based delegation.")

        # Initialize gRPC channel to orchestrator (optional)
        self.grpc_channel = None
        self.grpc_stub = None
        if grpc_endpoint and orchestrator_pb2_grpc:
            try:
                self.grpc_channel = grpc.insecure_channel(grpc_endpoint)
                self.grpc_stub = orchestrator_pb2_grpc.OrchestratorStub(self.grpc_channel)
                logger.info(f"Connected to gRPC orchestrator at {grpc_endpoint}")
            except Exception as e:
                logger.warning(f"Failed to connect to gRPC orchestrator: {e}. Continuing without gRPC.")

        # Initialize ROS publisher (optional)
        self.ros_pub = None
        if ros_topic:
            try:
                if not rospy.get_node_uri():
                    rospy.init_node('task_delegator', anonymous=True)
                self.ros_pub = rospy.Publisher(ros_topic, String, queue_size=10)
                logger.info(f"Initialized ROS publisher on topic {ros_topic}")
            except Exception as e:
                logger.warning(f"Failed to initialize ROS node: {e}. Continuing without ROS.")

        # Robot capabilities cache (robot_id -> {capability: strength})
        self.capabilities = self._load_capabilities()

    def _init_database(self):
        """Initialize database schema if tables don't exist."""
        cursor = self.db.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_type TEXT NOT NULL,
                robot_id TEXT,
                status TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS robot_capabilities (
                robot_id TEXT NOT NULL,
                capability TEXT NOT NULL,
                strength INTEGER NOT NULL,
                PRIMARY KEY (robot_id, capability)
            )
        """)
        # Insert default capabilities if table is empty
        cursor.execute("SELECT COUNT(*) FROM robot_capabilities")
        if cursor.fetchone()[0] == 0:
            default_caps = [
                ("Ford", "heavy_lifting", 90),
                ("Ford", "navigation", 70),
                ("Scion", "delicate_task", 85),
                ("Scion", "navigation", 80)
            ]
            cursor.executemany(
                "INSERT OR IGNORE INTO robot_capabilities (robot_id, capability, strength) VALUES (?, ?, ?)",
                default_caps
            )
        self.db.commit()

    def _load_capabilities(self) -> Dict[str, Dict[str, int]]:
        """Query robot capabilities from SQLite database."""
        try:
            cursor = self.db.cursor()
            cursor.execute("SELECT robot_id, capability, strength FROM robot_capabilities")
            capabilities = {}
            for row in cursor.fetchall():
                robot_id = row['robot_id']
                if robot_id not in capabilities:
                    capabilities[robot_id] = {}
                capabilities[robot_id][row['capability']] = row['strength']
            if not capabilities:
                logger.warning("No robot capabilities found in database")
            return capabilities
        except sqlite3.Error as e:
            logger.error(f"Failed to load capabilities: {e}")
            raise RuntimeError(f"Database query failed: {e}")

    def predict_task_suitability(self, task_type: str) -> Optional[str]:
        """Predict the best robot for a task using TensorFlow model or rule-based approach."""
        try:
            # If model is available, use it
            if self.model:
                task_types = ['heavy_lifting', 'delicate_task', 'navigation']
                if task_type not in task_types:
                    raise ValueError(f"Invalid task type: {task_type}")
                input_data = np.zeros(len(task_types))
                input_data[task_types.index(task_type)] = 1.0
                input_data = input_data.reshape(1, -1)

                predictions = self.model.predict(input_data, verbose=0)
                robot_ids = list(self.capabilities.keys())
                if not robot_ids:
                    raise RuntimeError("No robots available for prediction")
                best_robot_idx = np.argmax(predictions[0])
                if best_robot_idx >= len(robot_ids):
                    raise RuntimeError("Invalid robot index predicted")
                return robot_ids[best_robot_idx]
            else:
                # Rule-based fallback: find robot with highest capability for task type
                best_robot = None
                best_score = 0
                for robot_id, caps in self.capabilities.items():
                    if task_type in caps and caps[task_type] > best_score:
                        best_score = caps[task_type]
                        best_robot = robot_id
                return best_robot
        except Exception as e:
            logger.error(f"Task suitability prediction failed: {e}")
            return None

    def delegate_task(self, task_type: str) -> Dict[str, str]:
        """Delegate a task to the best robot via gRPC and ROS."""
        try:
            # Validate task type
            if not task_type:
                raise ValueError("Task type cannot be empty")

            # Predict best robot
            robot_id = self.predict_task_suitability(task_type)
            if not robot_id:
                raise RuntimeError(f"No suitable robot found for task {task_type}")

            # Verify robot capabilities
            if robot_id not in self.capabilities:
                raise RuntimeError(f"Robot {robot_id} not found in capabilities")
            if task_type not in self.capabilities[robot_id]:
                raise RuntimeError(f"Robot {robot_id} lacks capability for {task_type}")

            # Send task to orchestrator via gRPC (if available)
            if self.grpc_stub and orchestrator_pb2:
                try:
                    request = orchestrator_pb2.TaskRequest(task_type=task_type, robot_id=robot_id)
                    response = self.grpc_stub.DelegateTask(request)
                    if not response.success:
                        raise RuntimeError(f"Orchestrator rejected task: {response.message}")
                except Exception as e:
                    logger.warning(f"gRPC task delegation failed: {e}. Continuing without gRPC.")

            # Publish task to ROS topic (if available)
            if self.ros_pub:
                task_data = {"robot_id": robot_id, "task_type": task_type}
                try:
                    self.ros_pub.publish(json.dumps(task_data))
                    rospy.loginfo(f"Published task {task_type} to robot {robot_id}")
                except Exception as e:
                    logger.warning(f"ROS publishing failed: {e}")

            # Store task in database
            try:
                cursor = self.db.cursor()
                cursor.execute(
                    "INSERT INTO tasks (task_type, robot_id, status) VALUES (?, ?, ?)",
                    (task_type, robot_id, "assigned")
                )
                self.db.commit()
            except sqlite3.Error as e:
                logger.error(f"Failed to store task: {e}")
                raise RuntimeError(f"Database task storage failed: {e}")

            return {"status": "success", "robot_id": robot_id, "task_type": task_type}
        except Exception as e:
            logger.error(f"Task delegation failed: {e}")
            return {"status": "error", "message": str(e)}

    def __del__(self):
        """Clean up resources."""
        try:
            if hasattr(self, 'db') and self.db:
                self.db.close()
            if hasattr(self, 'grpc_channel') and self.grpc_channel:
                self.grpc_channel.close()
        except Exception as e:
            logger.warning(f"Cleanup failed: {e}")

# Example usage
if __name__ == "__main__":
    import sys
    try:
        delegator = TaskDelegator(
            model_path=os.getenv("MODEL_PATH", ""),
            db_path=os.getenv("DB_PATH", "mrtodp_tasks.db"),
            grpc_endpoint=os.getenv("GRPC_ENDPOINT", ""),
            ros_topic=os.getenv("ROS_TOPIC", "/mrtodp/tasks")
        )
        result = delegator.delegate_task("heavy_lifting")
        print(json.dumps(result, indent=2))
    except Exception as e:
        logger.error(f"Delegator initialization or execution failed: {e}")
        sys.exit(1)

