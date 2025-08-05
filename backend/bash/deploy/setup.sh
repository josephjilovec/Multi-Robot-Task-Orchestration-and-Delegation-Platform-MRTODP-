#!/bin/bash
# backend/bash/deploy/setup.sh
# Purpose: Automates setup for the Multi-Robot Task Orchestration and Delegation Platform (MRTODP).
# Installs dependencies for C++, Python, ROS, Julia, Lua, MATLAB, CUDA, TensorRT, and other components.
# Configures environment variables from .env.example for seamless integration with backend components
# (e.g., backend/cpp/robot_interface/, backend/python/ai_engine/delegator.py).
# Includes robust error handling for missing dependencies and installation failures, ensuring reliability
# for advanced users (e.g., robotics engineers, AI researchers) in a production environment.

# Exit on error
set -e

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Error handling function
handle_error() {
    log "ERROR: $1"
    exit 1
}

# Check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        handle_error "$1 not found. Please install $1."
    fi
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    handle_error "This script must be run as root (use sudo)."
fi

# Update package lists
log "Updating package lists..."
apt-get update || handle_error "Failed to update package lists"

# Install core dependencies
log "Installing core dependencies..."
apt-get install -y \
    build-essential \
    g++ \
    cmake \
    git \
    curl \
    wget \
    libcurl4-openssl-dev \
    libjansson-dev \
    nasm \
    lua5.4 \
    liblua5.4-dev || handle_error "Failed to install core dependencies"

# Install Python 3.10 and dependencies
log "Installing Python 3.10 and dependencies..."
apt-get install -y python3.10 python3.10-dev python3-pip || handle_error "Failed to install Python 3.10"
pip3 install --upgrade pip || handle_error "Failed to upgrade pip"
if [ -f "backend/python/requirements.txt" ]; then
    pip3 install -r backend/python/requirements.txt || handle_error "Failed to install Python dependencies"
else
    log "WARNING: backend/python/requirements.txt not found, skipping Python dependencies"
fi

# Install ROS Noetic
log "Installing ROS Noetic..."
if ! command -v roscore &> /dev/null; then
    sh -c 'echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros-latest.list'
    curl -s https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc | apt-key add - || handle_error "Failed to add ROS key"
    apt-get update
    apt-get install -y ros-noetic-desktop-full || handle_error "Failed to install ROS Noetic"
    echo "source /opt/ros/noetic/setup.bash" >> ~/.bashrc
    source /opt/ros/noetic/setup.bash
else
    log "ROS Noetic already installed"
fi

# Install Julia
log "Installing Julia..."
if ! command -v julia &> /dev/null; then
    JULIA_VERSION="1.9.3"
    wget https://julialang-s3.julialang.org/bin/linux/x64/1.9/julia-$JULIA_VERSION-linux-x86_64.tar.gz || handle_error "Failed to download Julia"
    tar -xvzf julia-$JULIA_VERSION-linux-x86_64.tar.gz -C /opt || handle_error "Failed to extract Julia"
    ln -s /opt/julia-$JULIA_VERSION/bin/julia /usr/local/bin/julia || handle_error "Failed to link Julia"
    rm julia-$JULIA_VERSION-linux-x86_64.tar.gz
    julia -e 'using Pkg; Pkg.add(["JSON", "ONNX"])' || handle_error "Failed to install Julia packages"
else
    log "Julia already installed"
fi

# Install CUDA 12.2 and TensorRT
log "Installing CUDA 12.2 and TensorRT..."
if ! command -v nvcc &> /dev/null; then
    wget https://developer.download.nvidia.com/compute/cuda/12.2.0/local_installers/cuda_12.2.0_535.86.10_linux.run || handle_error "Failed to download CUDA"
    sh cuda_12.2.0_535.86.10_linux.run --silent --toolkit || handle_error "Failed to install CUDA"
    rm cuda_12.2.0_535.86.10_linux.run
    echo "export PATH=/usr/local/cuda-12.2/bin:$PATH" >> ~/.bashrc
    echo "export LD_LIBRARY_PATH=/usr/local/cuda-12.2/lib64:$LD_LIBRARY_PATH" >> ~/.bashrc
    source ~/.bashrc
else
    log "CUDA already installed"
fi
# Note: TensorRT requires manual download from NVIDIA Developer portal
log "Please download and install TensorRT from https://developer.nvidia.com/tensorrt"

# Install MATLAB (placeholder, as MATLAB requires manual installation)
log "Checking for MATLAB..."
if ! command -v matlab &> /dev/null; then
    log "WARNING: MATLAB not found. Please install MATLAB R2016b+ manually from MathWorks."
else
    log "MATLAB already installed"
fi

# Configure environment variables from .env.example
log "Configuring environment variables..."
if [ -f ".env.example" ]; then
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        # Export variables
        export "$line" || handle_error "Failed to export environment variable: $line"
        echo "export $line" >> ~/.bashrc
    done < .env.example
    source ~/.bashrc
else
    handle_error ".env.example not found in project root"
fi

# Example .env variables for MRTODP
# Ensure key variables are set
log "Setting default environment variables if not present..."
[ -z "$ROBOT_INTERFACE_URL" ] && export ROBOT_INTERFACE_URL="http://localhost:50052" && echo "export ROBOT_INTERFACE_URL=http://localhost:50052" >> ~/.bashrc
[ -z "$TASK_FILE" ] && export TASK_FILE="tasks.json" && echo "export TASK_FILE=tasks.json" >> ~/.bashrc
[ -z "$RESULT_FILE" ] && export RESULT_FILE="results.json" && echo "export RESULT_FILE=results.json" >> ~/.bashrc
[ -z "$MODEL_PATH" ] && export MODEL_PATH="model.onnx" && echo "export MODEL_PATH=model.onnx" >> ~/.bashrc

# Verify installations
log "Verifying installations..."
check_command g++
check_command python3
check_command roscore
check_command julia
check_command lua5.4
check_command nvcc

# Create directory structure
log "Creating MRTODP directory structure..."
mkdir -p backend/{assembly,verilog,cuda,matlab,robot_langs/{krl,rapid,karel,val3,lua},cpp,python,julia} \
    tests/{c,cuda,matlab,robot_langs/{krl,rapid,karel,val3,lua}} \
    docs deploy .github/workflows || handle_error "Failed to create directory structure"

# Copy .env.example to .env if not exists
if [ ! -f ".env" ]; then
    cp .env.example .env || handle_error "Failed to copy .env.example to .env"
fi

# Clean up
log "Cleaning up..."
apt-get clean
rm -rf /var/lib/apt/lists/*

log "Setup completed successfully!"
exit 0
