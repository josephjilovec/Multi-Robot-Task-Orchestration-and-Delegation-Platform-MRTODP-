-- backend/lua/scripts/task.lua
-- Purpose: Implements lightweight task execution scripts for MRTODP using Lua 5.4.
-- Supports tasks like 'sort_items' for simple robots with basic motion and control.
-- Interfaces with backend/cpp/robot_interface/ via a shared memory interface for
-- command reception and status reporting. Includes robust error handling for
-- invalid inputs, shared memory issues, and execution failures, ensuring reliability
-- for advanced users (e.g., robotics engineers) in a production environment.

-- Load required modules (assumes FFI for shared memory access)
local ffi = require("ffi")

-- Define C-compatible shared memory structures
ffi.cdef[[
    typedef struct {
        int cmd_id;              // Command ID
        char task[64];           // Task name
        float params[6];         // Task parameters (e.g., position, velocity)
        int status;              // Status code (0: success, non-zero: error)
        char msg[128];           // Status message
    } shm_data_t;

    // Function to access shared memory (implemented in backend/cpp/robot_interface/)
    shm_data_t* get_shm_data();
]]

-- Constants
local SUCCESS = 0
local ERR_INVALID_TASK = 1
local ERR_EXECUTION_FAIL = 2
local ERR_SHM_FAIL = 3
local MAX_VELOCITY = 500.0      -- Max velocity (mm/s)
local POS_TOLERANCE = 0.1       -- Position tolerance (mm)

-- Task execution function
local function execute_task()
    -- Initialize variables
    local task_id = 0
    local task_name = ""
    local velocity = 100.0
    local target_pos = { x = 0, y = 0, z = 0, rx = 0 } -- Target position
    local tool_active = false
    local error_code = SUCCESS
    local status_msg = "Task initialized"

    -- Access shared memory
    local shm = ffi.C.get_shm_data()
    if shm == nil then
        error_code = ERR_SHM_FAIL
        status_msg = "Failed to access shared memory"
        return error_code, status_msg
    end

    -- Main execution loop
    while true do
        -- Read command from shared memory
        if shm.cmd_id > 0 then
            task_id = shm.cmd_id
            task_name = ffi.string(shm.task)
            velocity = shm.params[0]
            target_pos.x = shm.params[1]
            target_pos.y = shm.params[2]
            target_pos.z = shm.params[3]
            target_pos.rx = shm.params[4]
            tool_active = shm.params[5] > 0.0 -- Tool active if param > 0

            -- Validate parameters
            if task_name == "" then
                error_code = ERR_INVALID_TASK
                status_msg = "Invalid task name"
                goto error_handling
            end
            if velocity <= 0 or velocity > MAX_VELOCITY then
                error_code = ERR_INVALID_TASK
                status_msg = string.format("Invalid velocity: %.2f", velocity)
                goto error_handling
            end

            -- Execute task based on task_name
            if task_name == "sort_items" then
                -- Sort items task: Move to target position and activate tool
                local success, err = pcall(function()
                    -- Simulate motion (replace with actual robot API call)
                    local current_pos = { x = 0, y = 0, z = 0, rx = 0 } -- Mock current position
                    local dist = math.sqrt(
                        (current_pos.x - target_pos.x)^2 +
                        (current_pos.y - target_pos.y)^2 +
                        (current_pos.z - target_pos.z)^2
                    )
                    if dist > POS_TOLERANCE then
                        error("Motion failed: Target not reached")
                    end
                    if tool_active then
                        -- Simulate tool activation (e.g., gripper)
                        os.execute("sleep 2") -- Simulate 2s tool operation
                    end
                end)
                if not success then
                    error_code = ERR_EXECUTION_FAIL
                    status_msg = "Execution failed: " .. err
                    goto error_handling
                end
                error_code = SUCCESS
                status_msg = "Sort items completed"
            else
                -- Unsupported task
                error_code = ERR_INVALID_TASK
                status_msg = "Unsupported task: " .. task_name
                goto error_handling
            end

            -- Write status to shared memory
            shm.status = error_code
            ffi.copy(shm.msg, status_msg, math.min(#status_msg + 1, 128))
            shm.cmd_id = 0 -- Reset command ID to signal completion
        else
            -- No command available, wait
            os.execute("sleep 0.1")
        end
        ::continue::

        -- Error handling
        ::error_handling::
        if error_code ~= SUCCESS then
            shm.status = error_code
            ffi.copy(shm.msg, status_msg, math.min(#status_msg + 1, 128))
            shm.cmd_id = 0
            print("ERROR: " .. status_msg) -- Log to console (replace with CloudWatch in production)
            break -- Exit on error
        end
        ::loop_end::
    end

    return error_code, status_msg
end

-- Main entry point
local function main()
    local ok, err = pcall(execute_task)
    if not ok then
        print("FATAL ERROR: " .. err)
        return ERR_SHM_FAIL
    end
    return SUCCESS
end

-- Run the script
return main()
```
