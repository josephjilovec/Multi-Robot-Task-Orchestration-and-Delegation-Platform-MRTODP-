MRTODP Setup Guide
Overview
This document provides detailed instructions for setting up and running the Multi-Robot Task Orchestration and Delegation Platform (MRTODP) on a local development environment. It covers dependency installation, repository cloning, environment configuration, test execution, and containerized deployment using Docker and Kubernetes. The setup supports Ubuntu 22.04 (recommended) and targets advanced users (e.g., robotics engineers, AI developers). Troubleshooting steps are included for common issues, such as dependency conflicts and CUDA setup. Refer to architecture.md for system architecture and deploy/ for containerized deployment details.
System Requirements

OS: Ubuntu 22.04 (or compatible Linux distribution)
Hardware:
CPU: 4 cores, 8 threads (minimum)
RAM: 16 GB (minimum), 32 GB (recommended)
GPU: NVIDIA GPU with CUDA support (optional, for Julia neural network)
Disk: 50 GB free space


Network: Internet access for dependency downloads and repository cloning
Root Access: Required for installing system packages

Dependency Installation
MRTODP uses multiple languages and frameworks: C++, Python, ROS 2, Julia (1.10.0), Scala, Rust, Go, Java, and CUDA (12.2). Below are installation instructions for each.
1. C++ (GCC 11)
C++ is used for the task orchestrator (backend/cpp/task_manager/orchestrator.cpp) and requires Catch2 for testing.
sudo apt update
sudo apt install -y g++-11 make cmake
# Install Catch2 for testing
sudo apt install -y catch2

2. Python (3.10)
Python powers the AI engine (backend/python/ai_engine/delegator.py) with TensorFlow and gRPC.
sudo apt install -y python3.10 python3.10-dev python3-pip
pip3 install --upgrade pip
# Install dependencies
cd backend/python
pip3 install -r requirements.txt

Sample requirements.txt:
tensorflow==2.15.0
grpcio==1.62.0
pytest>=7.4.0
numpy>=1.26.0

3. ROS 2 (Humble Hawksbill)
ROS 2 enables robot communication (backend/cpp/task_manager/orchestrator.cpp).
sudo apt install -y software-properties-common
sudo add-apt-repository universe
sudo apt update && sudo apt install -y curl gnupg lsb-release
curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null
sudo apt update
sudo apt install -y ros-humble-desktop
source /opt/ros/humble/setup.bash

Add to ~/.bashrc:
echo "source /opt/ros/humble/setup.bash" >> ~/.bashrc

4. Julia (1.10.0)
Julia is used for neural networks (backend/julia/neural/network.jl) with Flux.jl.
wget https://julialang-s3.julialang.org/bin/linux/x64/1.10/julia-1.10.0-linux-x86_64.tar.gz
tar -xvzf julia-1.10.0-linux-x86_64.tar.gz
sudo mv julia-1.10.0 /opt/julia
sudo ln -s /opt/julia/bin/julia /usr/local/bin/julia
# Install dependencies
cd backend/julia
julia --project=. -e 'using Pkg; Pkg.instantiate()'

Sample Project.toml:
[deps]
Flux = "587475ba-b771-5e3f-ad9e-33799f191a9c"
Random = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[compat]
Flux = "0.14.0"

5. Scala (2.13)
Scala powers the marketplace API (backend/scala/src/main/scala/api.scala) with Akka HTTP.
sudo apt install -y openjdk-11-jdk
curl -fLo coursier https://git.io/coursier-cli
chmod +x coursier
./coursier setup
# Install sbt
curl -s https://raw.githubusercontent.com/sbt/sbt/v1.9.7/sbt -o /usr/local/bin/sbt
chmod +x /usr/local/bin/sbt
cd backend/scala
sbt update

Sample build.sbt:
name := "mrtodp-marketplace"
scalaVersion := "2.13.12"
libraryDependencies ++= Seq(
  "com.typesafe.akka" %% "akka-http" % "10.5.3",
  "com.typesafe.akka" %% "akka-stream" % "2.6.20",
  "org.postgresql" % "postgresql" % "42.7.3"
)

6. Rust (1.80)
Rust handles concurrent task scheduling (backend/rust/src/scheduler.rs) with Tokio and PyO3.
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
cd backend/rust
cargo build

Sample Cargo.toml:
[package]
name = "mrtodp-scheduler"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1.38.0", features = ["full"] }
pyo3 = { version = "0.20.0", features = ["auto-initialize"] }

[dev-dependencies]
tokio = { version = "1.38.0", features = ["full", "test-util"] }

7. Go (1.21)
Go is used for auxiliary services (assumed, e.g., backend/go/src/service.go).
wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
echo "export PATH=$PATH:/usr/local/go/bin" >> ~/.bashrc
source ~/.bashrc
cd backend/go
go mod tidy

Sample go.mod:
module mrtodp-service

go 1.21

require (
	github.com/gorilla/mux v1.8.1
)

8. Java (11)
Java supports additional integrations (assumed, e.g., backend/java/src/main/java/Service.java).
sudo apt install -y openjdk-11-jdk
cd backend/java
mvn install

Sample pom.xml:
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.mrtodp</groupId>
  <artifactId>service</artifactId>
  <version>1.0-SNAPSHOT</version>
  <dependencies>
    <dependency>
      <groupId>com.sparkjava</groupId>
      <artifactId>spark-core</artifactId>
      <version>2.9.4</version>
    </dependency>
  </dependencies>
</project>

9. CUDA (12.2)
CUDA enables GPU acceleration for Julia neural networks (backend/julia/neural/network.jl).
wget https://developer.download.nvidia.com/compute/cuda/12.2.0/local_installers/cuda_12.2.0_535.86.10_linux.run
sudo sh cuda_12.2.0_535.86.10_linux.run --silent --toolkit
echo "export PATH=$PATH:/usr/local/cuda-12.2/bin" >> ~/.bashrc
echo "export LD_LIBRARY_PATH=/usr/local/cuda-12.2/lib64:$LD_LIBRARY_PATH" >> ~/.bashrc
source ~/.bashrc

10. Other Dependencies

Node.js (18): For React frontend (frontend/).curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs
cd frontend
npm install

Sample package.json:{
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "axios": "^1.6.0",
    "chart.js": "^4.4.0",
    "tailwindcss": "^3.4.0"
  }
}


PostgreSQL: For Scala/Elixir marketplace (backend/scala/, backend/elixir/).sudo apt install -y postgresql postgresql-contrib
sudo -u postgres psql -c "CREATE DATABASE mrtodp;"


SQLite: For task storage (backend/cpp/, backend/lisp/).sudo apt install -y sqlite3 libsqlite3-dev


Common Lisp (SBCL): For task planner (backend/lisp/planner.lisp).sudo apt install -y sbcl
curl -O https://beta.quicklisp.org/quicklisp.lisp
sbcl --load quicklisp.lisp

In SBCL:(quicklisp-quickstart:install)
(ql:add-to-init-file)
(ql:quickload :fiveam)


Zig (0.11.0): For robot drivers (backend/zig/drivers/driver.zig).wget https://ziglang.org/download/0.11.0/zig-linux-x86_64-0.11.0.tar.xz
tar -xvf zig-linux-x86_64-0.11.0.tar.xz
sudo mv zig-linux-x86_64-0.11.0 /opt/zig
sudo ln -s /opt/zig/zig /usr/local/bin/zig


Ada (GNAT): For safety checks (backend/ada/safety/safety.adb).sudo apt install -y gnat



Repository Setup

Clone the Repository:
git clone https://github.com/<username>/mrtodp.git
cd mrtodp


Configure .env:Copy the example environment file and update it:
cp .env.example .env

Sample .env:
# Backend
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=mrtodp
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_password
SQLITE_DB_PATH=./data/tasks.db
ROS_MASTER_URI=http://localhost:11311
GRPC_SERVER=localhost:50051
# Frontend
REACT_APP_API_URL=http://localhost:8080
REACT_APP_WS_URL=ws://localhost:4000
# JWT
JWT_SECRET=your_jwt_secret


Initialize Databases:

SQLite:sqlite3 data/tasks.db < backend/cpp/task_manager/schema.sql

Sample schema.sql:CREATE TABLE tasks (id TEXT PRIMARY KEY, command TEXT, robot_id TEXT, parameters BLOB);
CREATE TABLE capabilities (robot_id TEXT, capability TEXT);


PostgreSQL:sudo -u postgres psql -d mrtodp -f backend/scala/src/main/resources/schema.sql

Sample schema.sql:CREATE TABLE skills (
  id VARCHAR(255) PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  robot_type VARCHAR(255) NOT NULL,
  description TEXT,
  code TEXT NOT NULL
);





Running the Application

Backend Services:

C++ Orchestrator:cd backend/cpp/task_manager
mkdir build && cd build
cmake .. && make
./orchestrator


Python AI Engine:cd backend/python/ai_engine
python3 cli.py


Julia Neural Network:cd backend/julia
julia --project=. -e 'include("neural/network.jl"); run_server()'


Common Lisp Planner:sbcl --load backend/lisp/planner.lisp


Rust Scheduler:cd backend/rust
cargo run


Scala API:cd backend/scala
sbt run


Elixir Server:cd backend/elixir
mix deps.get
mix phx.server


Go Service:cd backend/go
go run src/service.go


Java Service:cd backend/java
mvn exec:java




Frontend:
cd frontend
npm start

Access at http://localhost:3000.

Containerized Deployment:

Build Docker images:docker build -t mrtodp-backend -f deploy/Dockerfile.backend .
docker build -t mrtodp-frontend -f deploy/Dockerfile.frontend .


Run with Kubernetes:kubectl apply -f deploy/kubernetes.yml


See deploy/ for details.



Running Tests

C++ Tests:
cd backend/cpp/task_manager/build
ctest


Python Tests:
cd tests/python
pytest --cov=backend/python/ai_engine --cov-report=term-missing


Julia Tests:
cd tests/julia
julia --project=../backend/julia -e 'using Pkg; Pkg.test()'


Common Lisp Tests:
sbcl --load tests/lisp/test_planner.lisp

In SBCL:
(fiveam:run! 'planner-suite)


Rust Tests:
cd backend/rust
cargo test


Scala Tests:
cd backend/scala
sbt test


Elixir Tests:
cd backend/elixir
mix test


Frontend Tests:
cd frontend
npm test


Coverage Verification:

Python: Ensure ≥90% coverage in pytest output.
Rust: Use cargo-tarpaulin:cargo install cargo-tarpaulin
cargo tarpaulin --out Stdout





Troubleshooting

Dependency Conflicts:

Python: Run pipdeptree to identify conflicts:pip install pipdeptree
pipdeptree


Node.js: Run npm audit:npm audit fix




CUDA Issues:

Verify CUDA installation with nvidia-smi:nvidia-smi

Expected output:+-----------------------------------------------------------------------------+
| NVIDIA-SMI 535.86.10    Driver Version: 535.86.10    CUDA Version: 12.2     |
+-----------------------------------------------------------------------------+


If nvidia-smi fails, reinstall CUDA or update drivers:sudo apt install -y nvidia-driver-535 nvidia-utils-535




Database Connectivity:

SQLite: Ensure data/tasks.db exists and is writable.
PostgreSQL: Verify credentials in .env and check service:sudo systemctl status postgresql




ROS Issues:

Ensure ROS 2 is sourced:source /opt/ros/humble/setup.bash


Check ROS master:ros2 topic list




Frontend Issues:

Verify API URLs in .env match running backend services.
Check console logs in browser developer tools.


Test Failures:

Review test output for specific errors.
Ensure mocks are correctly configured (e.g., tests/python/test_delegator.py).



CI/CD Integration
The CI/CD pipeline (./github/workflows/ci.yml) automates dependency installation, building, and testing. Update it to include all languages:
name: CI
on:
  push:
    branches: [main]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Set up C++
        run: sudo apt install -y g++-11 cmake catch2
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'
      - name: Set up Julia
        uses: julia-actions/setup-julia@v1
        with:
          version: '1.10.0'
      - name: Set up Rust
        uses: actions-rs/toolchain@v1
        with:
          toolchain: stable
      - name: Set up Scala
        run: |
          curl -fLo coursier https://git.io/coursier-cli
          chmod +x coursier
          ./coursier setup
      - name: Set up Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'
      - name: Install Dependencies
        run: |
          cd backend/python && pip install -r requirements.txt
          cd backend/julia && julia --project=. -e 'using Pkg; Pkg.instantiate()'
          cd backend/rust && cargo build
          cd backend/scala && sbt update
          cd backend/elixir && mix deps.get
          cd frontend && npm install
      - name: Run Tests
        run: |
          cd backend/cpp/task_manager && mkdir build && cd build && cmake .. && make && ctest
          cd tests/python && pytest --cov=backend/python/ai_engine
          cd tests/julia && julia --project=../backend/julia -e 'using Pkg; Pkg.test()'
          cd backend/rust && cargo test
          cd backend/scala && sbt test
          cd backend/elixir && mix test
          cd frontend && npm test

Next Steps

Review architecture.md for system design.
Explore api.md for API details.
Deploy using deploy/Dockerfile and deploy/kubernetes.yml for production setup.

This guide ensures a robust setup for MRTODP development and testing.
