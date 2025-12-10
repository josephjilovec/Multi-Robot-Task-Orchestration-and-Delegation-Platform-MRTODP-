// frontend/src/components/Marketplace.js
// Purpose: Implements a React component for MRTODP using React 18 to provide a skills marketplace UI.
// Allows users to browse, upload, and download robot skills via /api/marketplace, interfacing with
// backend/elixir/marketplace/server.ex using axios. Integrates Chart.js for visualizing skill usage
// statistics (e.g., downloads per robot type). Styled with Tailwind CSS via CDN for a responsive,
// modern design. Includes robust error handling for API failures, invalid inputs, and visualization
// errors, targeting advanced users (e.g., robotics engineers, marketplace developers) in a production
// environment.

import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { Chart as ChartJS, ArcElement, Tooltip, Legend } from 'chart.js';
import { Pie } from 'react-chartjs-2';

// Register Chart.js components
ChartJS.register(ArcElement, Tooltip, Legend);

function Marketplace() {
  // State for skills, new skill form, error messages, and chart data
  const [skills, setSkills] = useState([]);
  const [newSkill, setNewSkill] = useState({
    id: '',
    name: '',
    robotType: '',
    code: '',
    metadata: {},
  });
  const [error, setError] = useState('');
  const [chartData, setChartData] = useState({
    labels: ['KUKA', 'ABB', 'FANUC', 'STAUBLI', 'LUA', 'CSHARP', 'ZIG'],
    datasets: [{
      label: 'Skill Downloads',
      data: [0, 0, 0, 0, 0, 0, 0],
      backgroundColor: [
        '#FF6384', '#36A2EB', '#FFCE56', '#4BC0C0', '#9966FF', '#FF9F40', '#C9CBCF'
      ],
    }],
  });

  // API URL from environment variable or default
  const apiUrl = process.env.REACT_APP_MARKETPLACE_URL || 'http://localhost:4000';

  // Fetch skills and usage data on component mount
  useEffect(() => {
    const fetchSkills = async () => {
      try {
        const response = await axios.get(`${apiUrl}/api/skills`);
        setSkills(response.data.skills || []);
        // Mock usage data (replace with actual API call)
        const usageResponse = await axios.get(`${apiUrl}/api/skills/usage`).catch(() => ({ data: null }));
        const usageData = usageResponse.data || {
          KUKA: 10, ABB: 15, FANUC: 8, STAUBLI: 5, LUA: 3, CSHARP: 7, ZIG: 4
        };
        setChartData({
          ...chartData,
          datasets: [{ ...chartData.datasets[0], data: Object.values(usageData) }],
        });
      } catch (err) {
        setError(`Failed to fetch skills: ${err.response?.data?.message || err.message}`);
      }
    };
    fetchSkills();
  }, [apiUrl]);

  // Handle input changes for new skill form
  const handleInputChange = (e) => {
    const { name, value } = e.target;
    if (name === 'metadata') {
      try {
        const metadata = JSON.parse(value);
        setNewSkill({ ...newSkill, metadata });
        setError('');
      } catch {
        setError('Invalid JSON for metadata');
      }
    } else {
      setNewSkill({ ...newSkill, [name]: value });
    }
  };

  // Handle skill upload
  const handleUploadSkill = async (e) => {
    e.preventDefault();
    if (!newSkill.id || !newSkill.name || !newSkill.robotType || !newSkill.code) {
      setError('All fields (ID, Name, Robot Type, Code) are required');
      return;
    }
    if (!['KUKA', 'ABB', 'FANUC', 'STAUBLI', 'LUA', 'CSHARP', 'ZIG'].includes(newSkill.robotType)) {
      setError('Invalid robot type');
      return;
    }

    try {
      const response = await axios.post(`${apiUrl}/api/skills`, newSkill);
      setSkills([...skills, response.data.skill]);
      setNewSkill({ id: '', name: '', robotType: '', code: '', metadata: {} });
      setError('');
      // Update chart data (mock increment)
      const newData = chartData.datasets[0].data.slice();
      const index = chartData.labels.indexOf(newSkill.robotType);
      if (index !== -1) newData[index]++;
      setChartData({ ...chartData, datasets: [{ ...chartData.datasets[0], data: newData }] });
    } catch (err) {
      setError(`Failed to upload skill: ${err.response?.data?.message || err.message}`);
    }
  };

  // Handle skill download
  const handleDownloadSkill = async (id) => {
    try {
      const response = await axios.get(`${apiUrl}/api/skills/${id}`);
      const skill = response.data.skill;
      // Trigger file download (simplified as JSON blob)
      const blob = new Blob([JSON.stringify(skill, null, 2)], { type: 'application/json' });
      const url = window.URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `skill_${id}.json`;
      link.click();
      window.URL.revokeObjectURL(url);
      // Update chart data (mock increment)
      const newData = chartData.datasets[0].data.slice();
      const index = chartData.labels.indexOf(skill.robotType);
      if (index !== -1) newData[index]++;
      setChartData({ ...chartData, datasets: [{ ...chartData.datasets[0], data: newData }] });
      setError('');
    } catch (err) {
      setError(`Failed to download skill ${id}: ${err.response?.data?.message || err.message}`);
    }
  };

  return (
    // Main container with Tailwind CSS styling and padding to account for fixed navbar
    <div className="container mx-auto px-4 py-8 pt-20">
      {/* Page title */}
      <h1 className="text-3xl font-bold text-gray-800 mb-6">Skills Marketplace</h1>

      {/* Error message display */}
      {error && (
        <div className="bg-red-100 border-l-4 border-red-500 text-red-700 p-4 mb-6 rounded">
          {error}
        </div>
      )}

      {/* Skill upload form */}
      <div className="bg-white p-6 rounded-lg shadow-md mb-8">
        <h2 className="text-xl font-semibold text-gray-700 mb-4">Upload New Skill</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <input
            type="text"
            name="id"
            value={newSkill.id}
            onChange={handleInputChange}
            placeholder="Skill ID"
            className="border rounded-md p-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
          <input
            type="text"
            name="name"
            value={newSkill.name}
            onChange={handleInputChange}
            placeholder="Skill Name"
            className="border rounded-md p-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
          <select
            name="robotType"
            value={newSkill.robotType}
            onChange={handleInputChange}
            className="border rounded-md p-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
          >
            <option value="">Select Robot Type</option>
            {chartData.labels.map(type => (
              <option key={type} value={type}>{type}</option>
            ))}
          </select>
          <textarea
            name="code"
            value={newSkill.code}
            onChange={handleInputChange}
            placeholder="Skill Code (e.g., PTP {...})"
            className="border rounded-md p-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
            rows="4"
          />
          <textarea
            name="metadata"
            value={JSON.stringify(newSkill.metadata, null, 2)}
            onChange={handleInputChange}
            placeholder="Metadata (JSON format)"
            className="border rounded-md p-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
            rows="4"
          />
        </div>
        <button
          onClick={handleUploadSkill}
          className="mt-4 bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition duration-300"
        >
          Upload Skill
        </button>
      </div>

      {/* Skill list */}
      <div className="bg-white p-6 rounded-lg shadow-md mb-8">
        <h2 className="text-xl font-semibold text-gray-700 mb-4">Available Skills</h2>
        {skills.length === 0 ? (
          <p className="text-gray-600">No skills available</p>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {skills.map(skill => (
              <div
                key={skill.id}
                className="border p-4 rounded-md bg-gray-50 hover:bg-gray-100 transition duration-200"
              >
                <p className="text-gray-800">
                  <strong>ID:</strong> {skill.id}<br />
                  <strong>Name:</strong> {skill.name}<br />
                  <strong>Robot Type:</strong> {skill.robotType}<br />
                  <strong>Metadata:</strong> {JSON.stringify(skill.metadata)}
                </p>
                <button
                  onClick={() => handleDownloadSkill(skill.id)}
                  className="mt-2 bg-green-600 text-white px-3 py-1 rounded-md hover:bg-green-700 transition duration-300"
                >
                  Download
                </button>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Skill usage visualization */}
      <div className="bg-white p-6 rounded-lg shadow-md">
        <h2 className="text-xl font-semibold text-gray-700 mb-4">Skill Usage by Robot Type</h2>
        <div className="max-w-md mx-auto">
          <Pie data={chartData} options={{
            responsive: true,
            plugins: {
              legend: { position: 'top' },
              tooltip: { enabled: true },
            },
          }} />
        </div>
      </div>
    </div>
  );
}

export default Marketplace;

