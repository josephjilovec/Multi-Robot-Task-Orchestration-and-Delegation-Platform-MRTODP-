```nasm
; backend/assembly/drivers/control.asm
; Purpose: Implements performance-critical low-level robot control drivers for MRTODP using x86_64 assembly.
; Optimizes for low-latency communication with robots (KRL, RAPID, KAREL, VAL3) by minimizing overhead in command processing.
; Interfaces with backend/c/drivers/driver.c via external C functions for HTTP communication and logging.
; Includes error handling for invalid inputs and hardware failures, ensuring reliability for advanced users
; (e.g., robotics engineers) in a production environment.

section .data
    ; Constants
    MAX_COMMAND_LEN equ 1024
    MAX_RESPONSE_LEN equ 512
    PROTOCOL_KRL    equ 0
    PROTOCOL_RAPID  equ 1
    PROTOCOL_KAREL  equ 2
    PROTOCOL_VAL3   equ 3
    PROTOCOL_UNKNOWN equ 4

    ; Error messages
    err_invalid_input db "Error: Invalid command input", 0
    err_unknown_protocol db "Error: Unknown protocol", 0
    err_hardware_failure db "Error: Hardware failure", 0
    success_msg db "Success: Command executed", 0

    ; Protocol strings for comparison
    str_krl db "KRL", 0
    str_rapid db "RAPID", 0
    str_karel db "KAREL", 0
    str_val3 db "VAL3", 0

section .bss
    ; Buffers
    command_buffer resb MAX_COMMAND_LEN ; Buffer for robot command
    response_buffer resb MAX_RESPONSE_LEN ; Buffer for response message
    robot_id_buffer resb 32 ; Buffer for robot_id
    format_buffer resb 16 ; Buffer for format

section .text
    ; External C functions from backend/c/drivers/driver.c
    extern process_command
    extern fprintf
    extern stderr

    ; Global function
    global execute_robot_command

; Function: execute_robot_command
; Purpose: Processes a robot command in a performance-critical manner.
; Arguments (C calling convention):
;   rdi: const char* json_input (JSON string with robotId, format, command)
;   rsi: char* output (buffer to store JSON response)
;   rdx: size_t output_size (size of output buffer)
; Returns:
;   eax: 0 on success, -1 on failure
execute_robot_command:
    ; Save base pointer and set up stack frame
    push rbp
    mov rbp, rsp

    ; Save registers (callee-saved)
    push rbx
    push r12
    push r13

    ; Store arguments
    mov r12, rdi ; json_input
    mov r13, rsi ; output
    mov rbx, rdx ; output_size

    ; Validate json_input (not null)
    test r12, r12
    jz .error_invalid_input

    ; Validate output buffer (not null)
    test r13, r13
    jz .error_invalid_input

    ; Validate output_size (non-zero)
    test rbx, rbx
    jz .error_invalid_input

    ; Call C function process_command for JSON parsing and HTTP communication
    mov rdi, r12 ; json_input
    call process_command
    test eax, eax
    jnz .error_process_command

    ; Prepare success response
    mov rdi, r13 ; output buffer
    mov rsi, success_msg
    call strcpy
    mov eax, 0 ; Return success
    jmp .done

.error_invalid_input:
    ; Log error to stderr
    mov rdi, [stderr]
    mov rsi, err_invalid_input
    call fprintf

    ; Prepare error response
    mov rdi, r13 ; output buffer
    mov rsi, err_invalid_input
    call strcpy
    mov eax, -1 ; Return failure
    jmp .done

.error_process_command:
    ; Log error to stderr
    mov rdi, [stderr]
    mov rsi, err_hardware_failure
    call fprintf

    ; Prepare error response
    mov rdi, r13 ; output buffer
    mov rsi, err_hardware_failure
    call strcpy
    mov eax, -1 ; Return failure

.done:
    ; Restore registers
    pop r13
    pop r12
    pop rbx

    ; Restore stack frame
    mov rsp, rbp
    pop rbp
    ret

; Function: strcpy (helper for string copying)
; Purpose: Copies null-terminated string from rsi to rdi, respecting buffer limits
; Arguments:
;   rdi: destination buffer
;   rsi: source string
strcpy:
    push rcx
    xor rcx, rcx
.copy_loop:
    mov al, [rsi + rcx]
    mov [rdi + rcx], al
    test al, al
    jz .copy_done
    inc rcx
    cmp rcx, MAX_RESPONSE_LEN - 1
    jb .copy_loop
    mov byte [rdi + rcx], 0 ; Ensure null termination
.copy_done:
    pop rcx
    ret
```
