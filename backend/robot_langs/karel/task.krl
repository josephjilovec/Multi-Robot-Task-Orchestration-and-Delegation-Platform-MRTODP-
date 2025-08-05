```
-- backend/robot_langs/karel/task.krl
-- Purpose: Implements a task execution script for FANUC robots in MRTODP using KAREL.
-- Supports tasks like 'move_object' with parameterized motion and tool control.
-- Interfaces with backend/cpp/robot_interface/ via a shared memory interface for
-- command reception and status reporting. Includes robust error handling for
-- motion failures, invalid parameters, and interface issues, ensuring reliability
-- for advanced users (e.g., robotics engineers) in a production environment.

PROGRAM TaskExecution
%COMMENT = 'MRTODP FANUC Task Execution'
%NOLOCKGROUP
%NOPAUSE = ERROR + COMMAND
%ENVIRONMENT shmem

-- Variable declarations
VAR
    task_id: INTEGER           -- Task identifier
    task_name: STRING[64]     -- Task name (e.g., "move_object")
    target_pos: POSITION       -- Target position for motion
    velocity: REAL             -- Motion velocity (mm/s)
    tool_active: BOOLEAN       -- Tool activation state
    error_code: INTEGER        -- Error code for status reporting
    status_msg: STRING[128]   -- Status message buffer
    shm_cmd_id: INTEGER       -- Shared memory: Command ID
    shm_task: STRING[64]      -- Shared memory: Task name
    shm_params: ARRAY[6] OF REAL -- Shared memory: Task parameters (position, velocity)
    shm_status: INTEGER       -- Shared memory: Status code (0: success, non-zero: error)
    shm_msg: STRING[128]      -- Shared memory: Status message

-- Constants
CONST
    SUCCESS = 0
    ERR_INVALID_TASK = 1
    ERR_MOTION_FAIL = 2
    ERR_SHM_FAIL = 3
    MAX_VELOCITY = 500.0    -- Max velocity (mm/s)
    POS_TOLERANCE = 0.1     -- Position tolerance (mm)

-- Initialize shared memory
BEGIN
    -- Register shared memory variables with backend/cpp/robot_interface/
    CONNECT SHARED shm_cmd_id TO 'SHM_CMD_ID'
    CONNECT SHARED shm_task TO 'SHM_TASK'
    CONNECT SHARED shm_params TO 'SHM_PARAMS'
    CONNECT SHARED shm_status TO 'SHM_STATUS'
    CONNECT SHARED shm_msg TO 'SHM_MSG'

    -- Initialize variables
    task_id = 0
    task_name = ''
    velocity = 100.0
    tool_active = FALSE
    error_code = SUCCESS
    status_msg = 'Task initialized'
    target_pos = POS(0, 0, 0, 0, 0, 0, 'WORLD') -- Default position

    -- Main execution loop
    WHILE TRUE DO
        -- Read command from shared memory
        IF shm_cmd_id > 0 THEN
            task_id = shm_cmd_id
            task_name = shm_task
            velocity = shm_params[1]
            target_pos.p.x = shm_params[2]
            target_pos.p.y = shm_params[3]
            target_pos.p.z = shm_params[4]
            target_pos.o.w = shm_params[5]
            tool_active = (shm_params[6] > 0.0) -- Tool active if param > 0

            -- Validate parameters
            IF task_name = '' THEN
                error_code = ERR_INVALID_TASK
                status_msg = 'Invalid task name'
                GOTO ERROR_HANDLING
            ENDIF
            IF velocity <= 0 OR velocity > MAX_VELOCITY THEN
                error_code = ERR_INVALID_TASK
                status_msg = 'Invalid velocity: ' + STR(velocity, 2)
                GOTO ERROR_HANDLING
            ENDIF

            -- Execute task based on task_name
            IF task_name = 'move_object' THEN
                -- Move object task: Move to target position and activate tool
                MOVE TO target_pos AT velocity, JOINT
                IF NOT POS_REACHED(target_pos, POS_TOLERANCE) THEN
                    error_code = ERR_MOTION_FAIL
                    status_msg = 'Motion failed: Target not reached'
                    GOTO ERROR_HANDLING
                ENDIF
                IF tool_active THEN
                    -- Activate gripper tool (e.g., DO[10])
                    SET_DO(10, TRUE) -- Assume digital output 10 controls tool
                    DELAY(2000)      -- Simulate gripping duration (2s)
                    SET_DO(10, FALSE)
                ENDIF
                error_code = SUCCESS
                status_msg = 'Move object completed'
            ELSE
                -- Unsupported task
                error_code = ERR_INVALID_TASK
                status_msg = 'Unsupported task: ' + task_name
                GOTO ERROR_HANDLING
            ENDIF

            -- Write status to shared memory
            shm_status = error_code
            shm_msg = status_msg
            shm_cmd_id = 0 -- Reset command ID to signal completion
        ELSE
            -- No command available, wait
            DELAY(100) -- 100ms delay
        ENDIF
        GOTO LOOP_END

    ERROR_HANDLING:
        -- Write error status to shared memory
        shm_status = error_code
        shm_msg = status_msg
        shm_cmd_id = 0
        WRITE('ERROR: ' + status_msg)
        PAUSE -- Halt execution on error

    LOOP_END:
    ENDWHILE
EXCEPTION
    WHEN EVENT = ERR_POS_NOT_REACHED THEN
        shm_status = ERR_MOTION_FAIL
        shm_msg = 'Motion error: Position not reached'
        shm_cmd_id = 0
        WRITE('ERROR: Position not reached')
        PAUSE
    WHEN EVENT = ERR_SHM_ACCESS THEN
        shm_status = ERR_SHM_FAIL
        shm_msg = 'Shared memory access error'
        shm_cmd_id = 0
        WRITE('ERROR: Shared memory failure')
        PAUSE
END TaskExecution

-- Utility routine to check if position is reached
ROUTINE POS_REACHED(pos: POSITION; tol: REAL): BOOLEAN
VAR
    act_pos: POSITION
    diff_x, diff_y, diff_z: REAL
BEGIN
    act_pos = CURPOS() -- Get current position
    diff_x = ABS(act_pos.p.x - pos.p.x)
    diff_y = ABS(act_pos.p.y - pos.p.y)
    diff_z = ABS(act_pos.p.z - pos.p.z)
    RETURN (diff_x < tol AND diff_y < tol AND diff_z < tol)
END POS_REACHED
```
