// frontend/src/components/Navbar.js
// Navigation bar component for MRTODP

import React from 'react';
import { Link } from 'react-router-dom';

function Navbar() {
  return (
    // Navigation bar with responsive design using Tailwind CSS
    <nav className="bg-blue-600 text-white p-4 shadow-md fixed w-full top-0 z-50">
      <div className="container mx-auto flex justify-between items-center">
        {/* Logo */}
        <div className="text-2xl font-bold">
          MRTODP
        </div>
        {/* Navigation links */}
        <div className="space-x-4">
          <Link
            to="/manager"
            className="hover:bg-blue-700 px-3 py-2 rounded-md transition duration-300"
          >
            Task Manager
          </Link>
          <Link
            to="/marketplace"
            className="hover:bg-blue-700 px-3 py-2 rounded-md transition duration-300"
          >
            Marketplace
          </Link>
        </div>
      </div>
    </nav>
  );
}

export default Navbar;

