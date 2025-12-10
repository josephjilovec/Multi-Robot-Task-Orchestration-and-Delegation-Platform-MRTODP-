# backend/python/cli.py
# Purpose: Implements a command-line interface (CLI) for MRTODP using Python 3.10 and Click.
# Provides commands to define tasks, assign robots, and monitor task status by interfacing with
# backend/python/ai_engine/delegator.py. Includes detailed help messages and robust error handling
# for invalid inputs, ensuring usability for advanced users (e.g., robotics engineers) in a
# production environment.

import os
from typing import Dict, Optional
import click
import json
import logging
from backend.python.ai_engine.delegator import TaskDelegator
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure logging for debugging and error tracking
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# CLI context settings for consistent formatting
CONTEXT_SETTINGS = dict(help_option_names=['-h', '--help'])

@click.group(context_settings=CONTEXT_SETTINGS)
@click.option('--model-path', default=None,
              help='Path to TensorFlow model for task delegation.')
@click.option('--db-path', default='mrtodp_tasks.db',
              help='Path to SQLite database for task storage.')
@click.option('--grpc-endpoint', default=None,
              help='gRPC endpoint for Orchestrator communication.')
@click.option('--ros-topic', default='/mrtodp/tasks',
              help='ROS topic for task publishing.')
@click.pass_context
def cli(ctx: click.Context, model_path: str, db_path: str, grpc_endpoint: str, ros_topic: str) -> None:
    """Multi-Robot Task Orchestration and Delegation Platform (MRTODP) CLI.

    Manages task definition, robot assignment, and status monitoring for heterogeneous robots.
    Interfaces with the AI-driven task delegator to optimize task allocation.
    """
    try:
        ctx.obj = TaskDelegator(
            model_path=model_path or os.getenv("MODEL_PATH", ""),
            db_path=db_path or os.getenv("DB_PATH", "mrtodp_tasks.db"),
            grpc_endpoint=grpc_endpoint or os.getenv("GRPC_ENDPOINT", ""),
            ros_topic=ros_topic or os.getenv("ROS_TOPIC", "/mrtodp/tasks")
        )
        logger.info("Initialized TaskDelegator for CLI")
    except Exception as e:
        logger.error(f"Failed to initialize TaskDelegator: {e}")
        raise click.ClickException(f"Initialization failed: {e}")

@cli.command()
@click.argument('task_type')
@click.pass_context
def define(ctx: click.Context, task_type: str) -> None:
    """Define and delegate a new task to a robot.

    TASK_TYPE: Type of task (e.g., heavy_lifting, delicate_task, navigation).

    Example: mrtodp define heavy_lifting
    """
    try:
        if not task_type:
            raise ValueError("Task type cannot be empty")
        delegator: TaskDelegator = ctx.obj
        result = delegator.delegate_task(task_type)
        if result['status'] == 'error':
            raise RuntimeError(result['message'])
        click.echo(json.dumps(result, indent=2))
        logger.info(f"Task {task_type} delegated successfully")
    except Exception as e:
        logger.error(f"Task definition failed: {e}")
        raise click.ClickException(f"Task definition failed: {e}")

@cli.command()
@click.argument('task_type')
@click.argument('robot_id')
@click.pass_context
def assign(ctx: click.Context, task_type: str, robot_id: str) -> None:
    """Manually assign a task to a specific robot.

    TASK_TYPE: Type of task (e.g., heavy_lifting, delicate_task).
    ROBOT_ID: ID of the robot (e.g., Ford, Scion).

    Example: mrtodp assign heavy_lifting Ford
    """
    try:
        if not task_type or not robot_id:
            raise ValueError("Task type and robot ID cannot be empty")
        delegator: TaskDelegator = ctx.obj
        # Validate robot capabilities
        if robot_id not in delegator.capabilities:
            raise ValueError(f"Robot {robot_id} not found in capabilities")
        if task_type not in delegator.capabilities[robot_id]:
            raise ValueError(f"Robot {robot_id} lacks capability for {task_type}")
        
        # Delegate task (will use the specified robot if it matches prediction)
        result = delegator.delegate_task(task_type)
        if result['status'] == 'error':
            raise RuntimeError(result['message'])
        if result['robot_id'] != robot_id:
            click.echo(f"Warning: Task assigned to {result['robot_id']} instead of {robot_id} based on AI prediction")
        click.echo(json.dumps(result, indent=2))
        logger.info(f"Task {task_type} assigned to robot {robot_id}")
    except Exception as e:
        logger.error(f"Task assignment failed: {e}")
        raise click.ClickException(f"Task assignment failed: {e}")

@cli.command()
@click.argument('task_id', type=int)
@click.pass_context
def monitor(ctx: click.Context, task_id: int) -> None:
    """Monitor the status of a task by ID.

    TASK_ID: ID of the task to monitor (integer).

    Example: mrtodp monitor 1
    """
    try:
        if task_id <= 0:
            raise ValueError("Task ID must be a positive integer")
        delegator: TaskDelegator = ctx.obj
        # Query task status from SQLite
        cursor = delegator.db.cursor()
        cursor.execute("SELECT id, task_type, robot_id, status FROM tasks WHERE id = ?", (task_id,))
        row = cursor.fetchone()
        if not row:
            raise RuntimeError(f"Task ID {task_id} not found")
        result = {
            "id": row['id'],
            "task_type": row['task_type'],
            "robot_id": row['robot_id'],
            "status": row['status']
        }
        click.echo(json.dumps(result, indent=2))
        logger.info(f"Monitored task ID {task_id}: {result['status']}")
    except Exception as e:
        logger.error(f"Task monitoring failed: {e}")
        raise click.ClickException(f"Task monitoring failed: {e}")

def main() -> None:
    """Run the MRTODP CLI."""
    try:
        cli()
    except Exception as e:
        logger.error(f"CLI execution failed: {e}")
        click.echo(f"Error: {e}", err=True)
        exit(1)

if __name__ == "__main__":
    main()

