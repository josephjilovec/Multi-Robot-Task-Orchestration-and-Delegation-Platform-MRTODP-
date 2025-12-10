#ifndef ORCHESTRATOR_HPP
#define ORCHESTRATOR_HPP

#include <string>
#include <vector>
#include <map>
#include <sqlite3.h>

class Orchestrator {
public:
    Orchestrator();
    ~Orchestrator();
    void delegateTask(const std::string& task_type);
    std::vector<std::map<std::string, std::string>> getTaskStatus(int task_id);

private:
    sqlite3* db_;
    void initDatabase();
    std::string queryAIEngine(const std::string& task_type);
    std::string selectRobotByCapability(const std::string& task_type);
    void storeTask(const std::string& task_type, const std::string& robot_id, const std::string& status);
    std::map<std::string, std::map<std::string, int>> robot_capabilities_;
};

#endif // ORCHESTRATOR_HPP

