// frontend/src/App.js
// Purpose: Implements the main React application component for MRTODP using React 18 and React Router.
// Sets up routes for TaskManager (/manager) and Marketplace (/marketplace) to manage robot tasks
// and access the skills marketplace. Includes a Navbar component for navigation and uses Tailwind CSS
// via CDN for responsive, modern styling. Designed for advanced users (e.g., robotics engineers,
// task planners) with a clean, intuitive UI supporting hybrid workflows in a production environment.

import React from 'react';
import { BrowserRouter as Router, Routes, Route, Link } from 'react-router-dom';
import TaskManager from './components/TaskManager';
import Marketplace from './components/Marketplace';
import Navbar from './components/Navbar';

// Main App component
function App() {
  return (
    // Set up Router for client-side routing
    <Router>
      {/* Main container with Tailwind CSS styling */}
      <div className="min-h-screen bg-gray-100">
        {/* Render Navbar */}
        <Navbar />
        {/* Define routes for TaskManager and Marketplace */}
        <Routes>
          <Route path="/manager" element={<TaskManager />} />
          <Route path="/marketplace" element={<Marketplace />} />
          {/* Default route redirects to TaskManager */}
          <Route path="/" element={<TaskManager />} />
        </Routes>
      </div>
    </Router>
  );
}

export default App;

