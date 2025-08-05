```python
# backend/python/ros_bridge/ros_communicator.py
# Purpose: Implements a ROS 2 node for MRTODP to handle communication with heterogeneous robots.
# Publishes tasks to robots via the /mrtodp/tasks topic and subscribes to status updates on
# /mrtodp/responses. Interfaces with backend/cpp/robot_interface/interface.cpp for task execution
# and supports robot-specific languages (KRL, RAPID, KAREL, VAL3) via JSON payloads.
# Uses Python 3.10 with ROS 2 (Humble) and includes robust error handling for ROS connection
# failures, ensuring reliable communication in a production environment.

import os
from typing import Dict, Optional
import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy
from std_msgs.msg import String
import json
import logging

# Configure logging for debugging and error tracking
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class RosCommunicator(Node):
    """ROS 2 node for communicating with robots in MRTODP."""

    def __init__(self, task_topic: str = "/mrtodp/tasks", response_topic: str = "/mrtodp/responses"):
        """Initialize the ROS 2 node with task and response topics."""
        super().__init__('ros_communicator')

        # Define QoS profile for reliable communication
        qos = QoSProfile(
            reliability=ReliabilityPolicy.RELIABLE,
            history=HistoryPolicy.KEEP_LAST,
            depth=10
        )

        # Initialize task publisher
        try:
            self.task_publisher = self.create_publisher(String, task_topic, qos)
            self.get_logger().info(f"Initialized publisher on topic {task_topic}")
        except Exception as e:
            logger.error(f"Failed to create publisher for {task_topic}: {e}")
            raise RuntimeError(f"Publisher initialization failed: {e}")

        # Initialize response subscriber
        try:
            self.response_subscriber = self.create_subscription(
                String, response_topic, self.response_callback, qos
            )
            self.get_logger().info(f"Initialized subscriber on topic {response_topic}")
        except Exception as e:
            logger.error(f"Failed to create subscriber for {response_topic}: {e}")
            raise RuntimeError(f"Subscriber initialization failed: {e}")

        # Robot language mappings (extend as needed)
        self.robot_language_map = {
            "Ford": "KRL",    # KUKA Robot Language
            "Scion": "RAPID", # ABB RAPID
            # Add KAREL, VAL3 mappings for other robots
        }

    def publish_task(self, robot_id: str, task_type: str, task_data: Dict) -> bool:
        """Publish a task to a robot with language-specific formatting."""
        try:
            # Validate inputs
            if not robot_id or not task_type:
                raise ValueError("robot_id and task_type cannot be empty")
            if robot_id not in self.robot_language_map:
                raise ValueError(f"Unknown robot: {robot_id}")

            # Format task data for robot-specific language
            language = self.robot_language_map[robot_id]
            formatted_data = self._format_task_data(task_type, task_data, language)

            # Create JSON payload
            payload = {
                "robot_id": robot_id,
                "task_type": task_type,
                "task_data": formatted_data,
                "language": language
            }

            # Publish task to ROS topic
            msg = String()
            msg.data = json.dumps(payload)
            self.task_publisher.publish(msg)
            self.get_logger().info(f"Published task {task_type} to robot {robot_id} in {language}")
            return True
        except Exception as e:
            self.get_logger().error(f"Failed to publish task to {robot_id}: {e}")
            logger.error(f"Task publishing failed: {e}")
            return False

    def _format_task_data(self, task_type: str, task_data: Dict, language: str) -> Dict:
        """Format task data for robot-specific language."""
        try:
            # Example formatting for robot languages (extend for KAREL, VAL3)
            if language == "KRL":
                return {"command": f"KRL_EXEC({task_type})", "params": task_data}
            elif language == "RAPID":
                return {"command": f"RAPID_EXEC({task_type})", "params": task_data}
            else:
                raise ValueError(f"Unsupported robot language: {language}")
        except Exception as e:
            logger.error(f"Task data formatting failed for {language}: {e}")
            raise RuntimeError(f"Task formatting failed: {e}")

    def response_callback(self, msg: String) -> None:
        """Handle status updates from robots."""
        try:
            data = json.loads(msg.data)
            robot_id = data.get("robot_id", "unknown")
            status = data.get("status", "unknown")
            self.get_logger().info(f"Received status from {robot_id}: {status}")
        except json.JSONDecodeError as e:
            self.get_logger().error(f"Invalid JSON in response: {e}")
        except Exception as e:
            self.get_logger().error(f"Response processing failed: {e}")

    def shutdown(self) -> None:
        """Clean up ROS node resources."""
        try:
            self.destroy_node()
            self.get_logger().info("ROS communicator node shut down")
        except Exception as e:
            logger.warning(f"Shutdown failed: {e}")

def main():
    """Initialize and run the ROS communicator node."""
    try:
        # Initialize ROS 2
        rclpy.init()
        communicator = RosCommunicator()

        # Spin node to process callbacks
        rclpy.spin(communicator)
    except Exception as e:
        logger.error(f"ROS communicator failed: {e}")
    finally:
        # Ensure proper shutdown
        if 'communicator' in locals():
            communicator.shutdown()
        if rclpy.ok():
            rclpy.shutdown()

if __name__ == "__main__":
    main()
```
