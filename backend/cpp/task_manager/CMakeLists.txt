cmake_minimum_required(VERSION 3.10)
project(MRTODP_Orchestrator)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find required packages
find_package(PkgConfig REQUIRED)
find_package(ros REQUIRED COMPONENTS roscpp std_msgs)

# Find SQLite3
find_library(SQLITE3_LIB sqlite3 REQUIRED)

# Find ZeroMQ
pkg_check_modules(ZMQ REQUIRED libzmq)

# Find nlohmann/json
find_path(NLOHMANN_JSON_INCLUDE_DIR nlohmann/json.hpp)
if(NOT NLOHMANN_JSON_INCLUDE_DIR)
    message(FATAL_ERROR "nlohmann/json not found. Install with: sudo apt install nlohmann-json3-dev")
endif()

# Include directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${ROS_INCLUDE_DIRS}
    ${ZMQ_INCLUDE_DIRS}
    ${NLOHMANN_JSON_INCLUDE_DIR}
)

# Source files
set(SOURCES
    orchestrator.cpp
)

# Executable
add_executable(orchestrator ${SOURCES})

# Link libraries
target_link_libraries(orchestrator
    ${ROS_LIBRARIES}
    ${SQLITE3_LIB}
    ${ZMQ_LIBRARIES}
)

# Install
install(TARGETS orchestrator DESTINATION bin)

