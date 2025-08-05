#include <dlfcn.h>
#include <ros/ros.h>
#include <std_msgs/String.h>
#include <string>
#include <map>
#include <stdexcept>
#include <memory>
#include <filesystem>
#include <vector>

// RobotInterface class for MRTODP: Provides a unified interface for communicating with
// heterogeneous robots using ROS and robot-specific languages (KRL, RAPID, KAREL, VAL3).
// Dynamically loads robot-specific drivers from backend/c/drivers/ and backend/assembly/drivers/.
// Receives tasks from Orchestrator (backend/cpp/task_manager/orchestrator.cpp) via ROS
// topic /mrtodp/tasks and dispatches them to appropriate robots. Includes error handling
// for communication failures and driver loading issues, ensuring robust operation.

class RobotInterface {
private:
    ros::NodeHandle ros_node_; // ROS node handle for communication
    ros::Subscriber task_subscriber_; // ROS subscriber for task messages
    std::map<std::string, void*> driver_handles_; // Map of robot_id to loaded driver handles
    std::map<std::string, std::string> robot_driver_map_; // Map of robot_id to driver file
    std::map<std::string, std::string> robot_language_map_; // Map of robot_id to language

    // Function pointer type for driver execution
    using ExecuteDriverFn = int (*)(const char* task_data, char* response, size_t response_size);

    // Initialize robot driver mappings
    void initRobotMappings() {
        // Example mappings; extend with actual robot configurations
        robot_driver_map_ = {
            {"Ford", "backend/c/drivers/ford_driver.so"},
            {"Scion", "backend/assembly/drivers/scion_driver.so"}
        };
        robot_language_map_ = {
            {"Ford", "KRL"}, // KUKA Robot Language for Ford
            {"Scion", "RAPID"} // ABB RAPID for Scion
        };
    }

    // Load a shared library driver
    void* loadDriver(const std::string& driver_path) {
        void* handle = dlopen(driver_path.c_str(), RTLD_LAZY);
        if (!handle) {
            throw std::runtime_error("Failed to load driver " + driver_path + ": " + dlerror());
        }
        return handle;
    }

    // Get driver function from shared library
    ExecuteDriverFn getDriverFunction(void* handle, const std::string& function_name) {
        void* func = dlsym(handle, function_name.c_str());
        if (!func) {
            throw std::runtime_error("Failed to load function " + function_name + ": " + dlerror());
        }
        return reinterpret_cast<ExecuteDriverFn>(func);
    }

    // Send task to robot using its specific language
    void sendToRobot(const std::string& robot_id, const std::string& task_data) {
        auto driver_it = driver_handles_.find(robot_id);
        if (driver_it == driver_handles_.end()) {
            throw std::runtime_error("No driver loaded for robot " + robot_id);
        }

        auto lang_it = robot_language_map_.find(robot_id);
        if (lang_it == robot_language_map_.end()) {
            throw std::runtime_error("No language mapping for robot " + robot_id);
        }

        // Translate task_data to robot-specific language (simplified example)
        std::string command;
        if (lang_it->second == "KRL") {
            command = "KRL_EXEC(" + task_data + ")";
        } else if (lang_it->second == "RAPID") {
            command = "RAPID_EXEC(" + task_data + ")";
        } else if (lang_it->second == "KAREL" || lang_it->second == "VAL3") {
            command = lang_it->second + "_EXEC(" + task_data + ")";
        } else {
            throw std::runtime_error("Unsupported robot language: " + lang_it->second);
        }

        // Execute driver function
        char response[256];
        ExecuteDriverFn execute = getDriverFunction(driver_it->second, "execute_task");
        int result = execute(command.c_str(), response, sizeof(response));
        if (result != 0) {
            throw std::runtime_error("Driver execution failed for robot " + robot_id + ": " + response);
        }

        // Publish response back to ROS for monitoring
        std_msgs::String msg;
        msg.data = response;
        ros::Publisher response_pub = ros_node_.advertise<std_msgs::String>("/mrtodp/responses", 10);
        response_pub.publish(msg);
        ros::spinOnce();
    }

    // Callback for ROS task messages
    void taskCallback(const std_msgs::String::ConstPtr& msg) {
        try {
            nlohmann::json task_data = nlohmann::json::parse(msg->data);
            if (!task_data.contains("robot_id") || !task_data.contains("task_type")) {
                ROS_ERROR("Invalid task data: missing robot_id or task_type");
                return;
            }

            std::string robot_id = task_data["robot_id"].get<std::string>();
            std::string task_type = task_data["task_type"].get<std::string>();
            sendToRobot(robot_id, task_type);
            ROS_INFO("Task %s sent to robot %s", task_type.c_str(), robot_id.c_str());
        } catch (const std::exception& e) {
            ROS_ERROR("Task processing failed: %s", e.what());
        }
    }

public:
    // Constructor: Initializes ROS and loads drivers
    RobotInterface() : ros_node_() {
        initRobotMappings();
        task_subscriber_ = ros_node_.subscribe("/mrtodp/tasks", 10, &RobotInterface::taskCallback, this);

        // Load drivers dynamically
        for (const auto& [robot_id, driver_path] : robot_driver_map_) {
            try {
                if (!std::filesystem::exists(driver_path)) {
                    throw std::runtime_error("Driver file " + driver_path + " does not exist");
                }
                driver_handles_[robot_id] = loadDriver(driver_path);
            } catch (const std::exception& e) {
                ROS_ERROR("Failed to load driver for robot %s: %s", robot_id.c_str(), e.what());
            }
        }
    }

    // Destructor: Closes driver handles
    ~RobotInterface() {
        for (auto& [robot_id, handle] : driver_handles_) {
            if (handle) {
                dlclose(handle);
            }
        }
    }

    // Check if a robot is available
    bool isRobotAvailable(const std::string& robot_id) const {
        return driver_handles_.find(robot_id) != driver_handles_.end() &&
               robot_language_map_.find(robot_id) != robot_language_map_.end();
    }
};

// Example usage
int main(int argc, char** argv) {
    ros::init(argc, argv, "mrtodp_robot_interface");
    try {
        RobotInterface interface;
        ROS_INFO("RobotInterface initialized, waiting for tasks on /mrtodp/tasks");
        ros::spin(); // Process ROS callbacks
    } catch (const std::exception& e) {
        ROS_ERROR("RobotInterface failed: %s", e.what());
        return 1;
    }
    return 0;
}
