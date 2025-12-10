#include <sqlite3.h>
#include <string>
#include <vector>
#include <map>
#include <stdexcept>
#include <memory>
#include <iostream>
#include <zmq.hpp>
#include <nlohmann/json.hpp>
#include <ros/ros.h>
#include <std_msgs/String.h>
#include <thread>
#include <mutex>

// Orchestrator class for MRTODP: Manages task delegation to heterogeneous robots based on
// their capabilities. Interfaces with Python AI engine (backend/python/ai_engine/) via ZeroMQ
// for task assignment recommendations and ROS (backend/python/ros_bridge/) for robot communication.
// Uses SQLite for persistent task storage. Implements error handling for unavailable robots
// and invalid tasks, ensuring robust operation in a production environment.

class Orchestrator {
private:
    sqlite3* db_; // SQLite database connection for task storage
    zmq::context_t zmq_context_; // ZeroMQ context for AI engine communication
    zmq::socket_t zmq_socket_; // ZeroMQ socket for request-response with AI engine
    ros::NodeHandle ros_node_; // ROS node handle for robot communication
    ros::Publisher task_publisher_; // ROS publisher for task commands
    std::mutex db_mutex_; // Mutex for thread-safe database operations

    // Robot capabilities map: robot_id -> {capability -> strength}
    std::map<std::string, std::map<std::string, int>> robot_capabilities_ = {
        {"Ford", {{"heavy_lifting", 90}, {"navigation", 70}}},
        {"Scion", {{"delicate_task", 85}, {"navigation", 80}}}
    };

    // Initialize SQLite database for task storage
    void initDatabase() {
        int rc = sqlite3_open("mrtodp_tasks.db", &db_);
        if (rc != SQLITE_OK) {
            throw std::runtime_error("Failed to open database: " + std::string(sqlite3_errmsg(db_)));
        }

        // Create tasks table if it doesn't exist
        const char* create_table_sql = 
            "CREATE TABLE IF NOT EXISTS tasks ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT, "
            "task_type TEXT NOT NULL, "
            "robot_id TEXT, "
            "status TEXT NOT NULL, "
            "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);";
        char* err_msg = nullptr;
        {
            std::lock_guard<std::mutex> lock(db_mutex_);
            rc = sqlite3_exec(db_, create_table_sql, nullptr, nullptr, &err_msg);
            if (rc != SQLITE_OK) {
                std::string error = "Failed to create tasks table: " + std::string(err_msg);
                sqlite3_free(err_msg);
                throw std::runtime_error(error);
            }
        }
    }

    // Send task to AI engine via ZeroMQ and get recommended robot
    std::string queryAIEngine(const std::string& task_type) {
        try {
            nlohmann::json request = {{"task_type", task_type}};
            std::string request_str = request.dump();
            zmq_socket_.send(zmq::buffer(request_str), zmq::send_flags::none);

            zmq::message_t reply;
            auto result = zmq_socket_.recv(reply, zmq::recv_flags::none);
            if (!result.has_value()) {
                throw std::runtime_error("No response from AI engine");
            }
            
            std::string reply_str(static_cast<char*>(reply.data()), reply.size());
            auto response = nlohmann::json::parse(reply_str);
            
            if (!response.contains("robot_id") || !response["robot_id"].is_string()) {
                throw std::runtime_error("Invalid AI engine response: missing or invalid robot_id");
            }
            return response["robot_id"].get<std::string>();
        } catch (const std::exception& e) {
            // Fallback to rule-based selection if AI engine unavailable
            std::cerr << "AI engine query failed: " << e.what() << ", using fallback" << std::endl;
            return selectRobotByCapability(task_type);
        }
    }

    // Fallback: Select robot based on capabilities
    std::string selectRobotByCapability(const std::string& task_type) {
        std::string best_robot;
        int best_score = 0;
        for (const auto& [robot_id, caps] : robot_capabilities_) {
            if (caps.find(task_type) != caps.end() && caps.at(task_type) > best_score) {
                best_score = caps.at(task_type);
                best_robot = robot_id;
            }
        }
        if (best_robot.empty()) {
            throw std::runtime_error("No robot found with capability: " + task_type);
        }
        return best_robot;
    }

    // Store task in SQLite database
    void storeTask(const std::string& task_type, const std::string& robot_id, const std::string& status) {
        const char* insert_sql = 
            "INSERT INTO tasks (task_type, robot_id, status) VALUES (?, ?, ?);";
        sqlite3_stmt* stmt;
        {
            std::lock_guard<std::mutex> lock(db_mutex_);
            int rc = sqlite3_prepare_v2(db_, insert_sql, -1, &stmt, nullptr);
            if (rc != SQLITE_OK) {
                throw std::runtime_error("Failed to prepare insert statement: " + std::string(sqlite3_errmsg(db_)));
            }

            sqlite3_bind_text(stmt, 1, task_type.c_str(), -1, SQLITE_STATIC);
            sqlite3_bind_text(stmt, 2, robot_id.c_str(), -1, SQLITE_STATIC);
            sqlite3_bind_text(stmt, 3, status.c_str(), -1, SQLITE_STATIC);

            rc = sqlite3_step(stmt);
            if (rc != SQLITE_DONE) {
                sqlite3_finalize(stmt);
                throw std::runtime_error("Failed to insert task: " + std::string(sqlite3_errmsg(db_)));
            }
            sqlite3_finalize(stmt);
        }
    }

public:
    // Constructor: Initializes SQLite, ZeroMQ, and ROS
    Orchestrator() : zmq_context_(1), zmq_socket_(zmq_context_, ZMQ_REQ), ros_node_() {
        // Initialize SQLite database
        initDatabase();

        // Connect to AI engine (assumes Python AI engine at localhost:5555)
        try {
            zmq_socket_.connect("tcp://localhost:5555");
            zmq_socket_.set(zmq::sockopt::rcvtimeo, 2000); // 2 second timeout
        } catch (const zmq::error_t& e) {
            std::cerr << "Warning: Failed to connect to AI engine: " << e.what() << ", will use fallback" << std::endl;
        }

        // Initialize ROS publisher (assumes topic /mrtodp/tasks)
        task_publisher_ = ros_node_.advertise<std_msgs::String>("/mrtodp/tasks", 10);
    }

    // Destructor: Closes database and ZeroMQ socket
    ~Orchestrator() {
        if (db_) {
            sqlite3_close(db_);
        }
    }

    // Delegate a task to a robot based on task type and capabilities
    void delegateTask(const std::string& task_type) {
        // Validate task type
        if (task_type.empty()) {
            throw std::invalid_argument("Task type cannot be empty");
        }

        // Query AI engine for recommended robot
        std::string robot_id;
        try {
            robot_id = queryAIEngine(task_type);
        } catch (const std::exception& e) {
            throw std::runtime_error("AI engine query failed: " + std::string(e.what()));
        }

        // Verify robot exists and has capability
        if (robot_capabilities_.find(robot_id) == robot_capabilities_.end()) {
            throw std::runtime_error("Robot " + robot_id + " not found");
        }
        if (task_type == "heavy_lifting" && robot_capabilities_[robot_id]["heavy_lifting"] < 50) {
            throw std::runtime_error("Robot " + robot_id + " lacks sufficient heavy_lifting capability");
        }
        if (task_type == "delicate_task" && robot_capabilities_[robot_id]["delicate_task"] < 50) {
            throw std::runtime_error("Robot " + robot_id + " lacks sufficient delicate_task capability");
        }

        // Store task in database
        try {
            storeTask(task_type, robot_id, "assigned");
        } catch (const std::exception& e) {
            throw std::runtime_error("Failed to store task: " + std::string(e.what()));
        }

        // Publish task to robot via ROS
        std_msgs::String msg;
        nlohmann::json task_data = {{"robot_id", robot_id}, {"task_type", task_type}};
        msg.data = task_data.dump();
        task_publisher_.publish(msg);
        ros::spinOnce(); // Process ROS callbacks
    }

    // Retrieve task status from database
    std::vector<std::map<std::string, std::string>> getTaskStatus(int task_id) {
        std::vector<std::map<std::string, std::string>> result;
        const char* select_sql = "SELECT id, task_type, robot_id, status, created_at FROM tasks WHERE id = ?;";
        sqlite3_stmt* stmt;

        {
            std::lock_guard<std::mutex> lock(db_mutex_);
            int rc = sqlite3_prepare_v2(db_, select_sql, -1, &stmt, nullptr);
            if (rc != SQLITE_OK) {
                throw std::runtime_error("Failed to prepare select statement: " + std::string(sqlite3_errmsg(db_)));
            }

            sqlite3_bind_int(stmt, 1, task_id);

            while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
                std::map<std::string, std::string> task;
                task["id"] = std::to_string(sqlite3_column_int(stmt, 0));
                task["task_type"] = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 1));
                task["robot_id"] = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 2));
                task["status"] = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 3));
                task["created_at"] = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 4));
                result.push_back(task);
            }

            if (rc != SQLITE_DONE && rc != SQLITE_ROW) {
                sqlite3_finalize(stmt);
                throw std::runtime_error("Failed to query tasks: " + std::string(sqlite3_errmsg(db_)));
            }
            sqlite3_finalize(stmt);
        }

        if (result.empty()) {
            throw std::runtime_error("Task ID " + std::to_string(task_id) + " not found");
        }
        return result;
    }
};

// Example usage
int main(int argc, char** argv) {
    ros::init(argc, argv, "mrtodp_orchestrator");
    try {
        Orchestrator orchestrator;
        orchestrator.delegateTask("heavy_lifting"); // Delegate a heavy lifting task
        auto status = orchestrator.getTaskStatus(1); // Query task status
        for (const auto& task : status) {
            std::cout << "Task ID: " << task.at("id") << ", Type: " << task.at("task_type")
                      << ", Robot: " << task.at("robot_id") << ", Status: " << task.at("status") << std::endl;
        }
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }
    return 0;
}

