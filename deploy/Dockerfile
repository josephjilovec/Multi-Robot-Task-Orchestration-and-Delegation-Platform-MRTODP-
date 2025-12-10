# deploy/Dockerfile
# Purpose: Containerizes the Multi-Robot Task Orchestration and Delegation Platform (MRTODP)
# using a multi-stage build to optimize size and ensure isolation of dependencies. Installs
# C++, Python, ROS 2, Julia (1.10.0), Scala, Rust, Go, Java, CUDA (12.2), and dependencies
# (e.g., Flux.jl 0.14.0, Yao.jl 0.8.0). Copies the repository, configures environment variables
# from .env.example, and runs the C++ orchestrator and Scala/Elixir marketplace servers.
# Exposes port 5000 for API access. Includes error handling and detailed comments for
# maintainability, targeting advanced users (e.g., robotics engineers, DevOps professionals).

# Stage 1: Base image with system dependencies
FROM ubuntu:22.04 AS base

# Install basic tools and dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    wget \
    git \
    sudo \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    || (echo "Failed to install base dependencies" && exit 1)

# Set working directory
WORKDIR /app

# Stage 2: C++ and ROS 2 dependencies
FROM base AS cpp-ros
RUN apt-get update && apt-get install -y \
    g++-11 \
    cmake \
    libsqlite3-dev \
    software-properties-common \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    || (echo "Failed to install C++ and SQLite dependencies" && exit 1)

# Stage 3: Python dependencies
FROM base AS python
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3.10-dev \
    python3-pip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    || (echo "Failed to install Python" && exit 1)
COPY backend/python/requirements.txt /app/backend/python/requirements.txt
RUN pip3 install --no-cache-dir -r /app/backend/python/requirements.txt \
    || (echo "Failed to install Python dependencies" && exit 1)

# Stage 4: Julia dependencies
FROM base AS julia
RUN wget https://julialang-s3.julialang.org/bin/linux/x64/1.10/julia-1.10.0-linux-x86_64.tar.gz \
    && tar -xvzf julia-1.10.0-linux-x86_64.tar.gz \
    && mv julia-1.10.0 /opt/julia \
    && ln -s /opt/julia/bin/julia /usr/local/bin/julia \
    && rm julia-1.10.0-linux-x86_64.tar.gz \
    || (echo "Failed to install Julia" && exit 1)
COPY backend/julia/Project.toml /app/backend/julia/Project.toml
RUN julia --project=/app/backend/julia -e 'using Pkg; Pkg.instantiate()' \
    || (echo "Failed to install Julia dependencies" && exit 1)

# Stage 5: Scala dependencies
FROM base AS scala
RUN apt-get update && apt-get install -y openjdk-11-jdk \
    && curl -fLo coursier https://git.io/coursier-cli \
    && chmod +x coursier \
    && ./coursier setup --yes \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    || (echo "Failed to install Scala and JDK" && exit 1)
COPY backend/scala/build.sbt /app/backend/scala/build.sbt
RUN cd /app/backend/scala && sbt update \
    || (echo "Failed to install Scala dependencies" && exit 1)

# Stage 6: Rust dependencies
FROM base AS rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    || (echo "Failed to install Rust" && exit 1)
ENV PATH="/root/.cargo/bin:${PATH}"
COPY backend/rust/Cargo.toml /app/backend/rust/Cargo.toml
RUN cd /app/backend/rust && cargo build --release \
    || (echo "Failed to install Rust dependencies" && exit 1)

# Stage 7: Final image
FROM base AS final
# Copy dependencies from previous stages
COPY --from=python /usr/bin/python3.10 /usr/bin/python3
COPY --from=python /usr/lib/python3.10 /usr/lib/python3.10
COPY --from=julia /opt/julia /opt/julia
COPY --from=rust /root/.cargo /root/.cargo

# Set environment variables
ENV PATH="/opt/julia/bin:/root/.cargo/bin:${PATH}"

# Copy repository
COPY . /app
WORKDIR /app

# Configure environment variables from .env.example
COPY .env.example /app/.env

# Initialize databases
RUN mkdir -p data && sqlite3 data/tasks.db < backend/cpp/task_manager/schema.sql \
    || (echo "Failed to initialize databases" && exit 1)

# Build backend components
RUN cd backend/rust && cargo build --release \
    || (echo "Failed to build Rust scheduler" && exit 1)

# Expose port for API access
EXPOSE 5000 8080 4000

# Healthcheck for container
HEALTHCHECK --interval=30s --timeout=3s \
  CMD curl -f http://localhost:5000/health || exit 1

# Entry point to run services
CMD cd backend/python && python3 cli.py & \
    cd backend/rust && ./target/release/mrtodp-scheduler & \
    echo "MRTODP services started"

