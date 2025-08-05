```
; backend/robot_langs/krl/task.krl
; Purpose: Implements a task execution script for KUKA robots in MRTODP using KRL.
; Supports tasks like 'clean kitchen' with parameterized motion and tool control.
; Interfaces with backend/cpp/robot_interface/ via a shared memory interface for
; command reception and status reporting. Includes robust error handling for
; motion failures, invalid parameters, and interface issues, ensuring reliability
; for advanced users (e.g., robotics engineers) in a production environment.

; Global variables
GLOBAL DEF TaskExecution()
  ; Task parameters
  DECL CHAR task_name[64]   ; Task name (e.g., "clean_kitchen")
  DECL INT task_id          ; Task identifier
  DECL E6POS target_pos     ; Target position for motion
  DECL REAL velocity        ; Motion velocity (mm/s)
  DECL BOOL tool_active     ; Tool activation state
  DECL INT error_code       ; Error code for status reporting
  DECL CHAR status_msg[128] ; Status message buffer

  ; Interface variables (shared memory with backend/cpp/robot_interface/)
  DECL GLOBAL INT shm_cmd_id      ; Shared memory: Command ID
  DECL GLOBAL CHAR shm_task[64]   ; Shared memory: Task name
  DECL GLOBAL REAL shm_params[6]  ; Shared memory: Task parameters (e.g., position, velocity)
  DECL GLOBAL INT shm_status      ; Shared memory: Status code (0: success, non-zero: error)
  DECL GLOBAL CHAR shm_msg[128]   ; Shared memory: Status message

  ; Constants
  DECL CONST INT SUCCESS = 0
  DECL CONST INT ERR_INVALID_TASK = 1
  DECL CONST INT ERR_MOTION_FAIL = 2
  DECL CONST INT ERR_SHM_FAIL = 3
  DECL CONST REAL MAX_VELOCITY = 500.0 ; Max velocity (mm/s)

  ; Initialize variables
  task_id = 0
  task_name[] = ""
  velocity = 100.0
  tool_active = FALSE
  error_code = SUCCESS
  status_msg[] = "Task initialized"

  ; Main execution loop
  LOOP
    ; Read command from shared memory (backend/cpp/robot_interface/)
    IF shm_cmd_id > 0 THEN
      task_id = shm_cmd_id
      STRUC_CLEAR(task_name)
      STRUC_COPY(shm_task, task_name)
      velocity = shm_params[0]
      target_pos.X = shm_params[1]
      target_pos.Y = shm_params[2]
      target_pos.Z = shm_params[3]
      target_pos.A = shm_params[4]
      target_pos.B = shm_params[5]
      tool_active = (shm_params[5] > 0.0) ; Tool active if B > 0

      ; Validate parameters
      IF STRLEN(task_name) == 0 THEN
        error_code = ERR_INVALID_TASK
        STRUC_CLEAR(status_msg)
        STRUC_COPY("Invalid task name", status_msg)
        GOTO error_handling
      ENDIF
      IF velocity <= 0 OR velocity > MAX_VELOCITY THEN
        error_code = ERR_INVALID_TASK
        STRUC_CLEAR(status_msg)
        STRUC_COPY("Invalid velocity", status_msg)
        GOTO error_handling
      ENDIF

      ; Execute task based on task_name
      IF STRCOMP(task_name, "clean_kitchen") THEN
        ; Clean kitchen task: Move to target position and activate tool
        PTP target_pos VEL=velocity ; Point-to-point motion
        IF $POS_ACT <> target_pos THEN
          error_code = ERR_MOTION_FAIL
          STRUC_CLEAR(status_msg)
          STRUC_COPY("Motion failed: Target not reached", status_msg)
          GOTO error_handling
        ENDIF
        IF tool_active THEN
          ; Activate cleaning tool (e.g., vacuum)
          OUT 10 TRUE ; Assume output 10 controls tool
          WAIT SEC 2.0 ; Simulate cleaning duration
          OUT 10 FALSE
        ENDIF
        error_code = SUCCESS
        STRUC_CLEAR(status_msg)
        STRUC_COPY("Clean kitchen completed", status_msg)
      ELSE
        ; Unsupported task
        error_code = ERR_INVALID_TASK
        STRUC_CLEAR(status_msg)
        STRUC_COPY("Unsupported task", status_msg)
        GOTO error_handling
      ENDIF

      ; Write status to shared memory
      shm_status = error_code
      STRUC_CLEAR(shm_msg)
      STRUC_COPY(status_msg, shm_msg)
      shm_cmd_id = 0 ; Reset command ID to signal completion
    ELSE
      ; No command available, wait
      WAIT SEC 0.1
    ENDIF
    GOTO loop_end

    error_handling:
      ; Write error status to shared memory
      shm_status = error_code
      STRUC_CLEAR(shm_msg)
      STRUC_COPY(status_msg, shm_msg)
      shm_cmd_id = 0 ; Reset command ID
      HALT ; Pause execution on error

    loop_end:
  ENDLOOP
END TaskExecution

; Error handling subroutine
GLOBAL DEF HandleError(error_code:IN, msg:IN)
  DECL INT error_code
  DECL CHAR msg[128]
  ; Log error to system log (KUKA-specific)
  $ERROR = error_code
  $MSG = msg
  HALT ; Stop execution
END HandleError
```
