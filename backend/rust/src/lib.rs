```rust
// backend/rust/src/lib.rs
// Purpose: Implements a concurrent scheduling library for MRTODP using Rust and Tokio.
// Provides low-latency task scheduling for heterogeneous robots, interfacing with
// backend/python/ai_engine/delegator.py via Foreign Function Interface (FFI).
// Uses Tokio for async concurrency and ensures thread-safe operations. Includes
// robust error handling for invalid inputs and FFI failures, optimized for
// production use by advanced users (e.g., robotics engineers).

use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio::task;
use serde::{Deserialize, Serialize};
use serde_json;

// Task struct for scheduling
#[derive(Serialize, Deserialize, Clone)]
struct Task {
    id: u32,
    task_type: String,
    priority: u32,
    robot_id: Option<String>,
}

// Scheduler struct for managing tasks
struct Scheduler {
    tasks: Arc<Mutex<HashMap<u32, Task>>>,
}

impl Scheduler {
    // Initialize a new scheduler
    fn new() -> Self {
        Scheduler {
            tasks: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    // Schedule a task asynchronously
    async fn schedule_task(&self, task: Task) -> Result<(), String> {
        let mut tasks = self.tasks.lock().await;
        if tasks.contains_key(&task.id) {
            return Err(format!("Task ID {} already exists", task.id));
        }
        tasks.insert(task.id, task.clone());
        Ok(())
    }

    // Retrieve task status
    async fn get_task_status(&self, task_id: u32) -> Option<Task> {
        let tasks = self.tasks.lock().await;
        tasks.get(&task_id).cloned()
    }
}

// Global scheduler instance for FFI
lazy_static::lazy_static! {
    static ref SCHEDULER: Arc<Scheduler> = Arc::new(Scheduler::new());
}

// FFI function to schedule a task from Python
#[no_mangle]
pub extern "C" fn schedule_task_ffi(task_json: *const c_char) -> *mut c_char {
    // Convert C string to Rust string
    let task_json = unsafe {
        if task_json.is_null() {
            return CString::new("Error: Null task JSON").unwrap().into_raw();
        }
        match CStr::from_ptr(task_json).to_str() {
            Ok(s) => s,
            Err(_) => return CString::new("Error: Invalid task JSON").unwrap().into_raw(),
        }
    };

    // Parse JSON into Task
    let task: Task = match serde_json::from_str(task_json) {
        Ok(task) => task,
        Err(e) => return CString::new(format!("Error: JSON parsing failed: {}", e)).unwrap().into_raw(),
    };

    // Spawn async task for scheduling
    let runtime = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(e) => return CString::new(format!("Error: Tokio runtime creation failed: {}", e)).unwrap().into_raw(),
    };

    let result = runtime.block_on(async {
        SCHEDULER.schedule_task(task).await
    });

    // Return result as C string
    match result {
        Ok(()) => CString::new("Success").unwrap().into_raw(),
        Err(e) => CString::new(format!("Error: {}", e)).unwrap().into_raw(),
    }
}

// FFI function to get task status from Python
#[no_mangle]
pub extern "C" fn get_task_status_ffi(task_id: u32) -> *mut c_char {
    let runtime = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(e) => return CString::new(format!("Error: Tokio runtime creation failed: {}", e)).unwrap().into_raw(),
    };

    let task = runtime.block_on(async {
        SCHEDULER.get_task_status(task_id).await
    });

    match task {
        Some(task) => match serde_json::to_string(&task) {
            Ok(json) => CString::new(json).unwrap().into_raw(),
            Err(e) => CString::new(format!("Error: JSON serialization failed: {}", e)).unwrap().into_raw(),
        },
        None => CString::new("Error: Task not found").unwrap().into_raw(),
    }
}

// FFI function to free C string memory
#[no_mangle]
pub extern "C" fn free_string_ffi(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

// Example async function for internal testing
#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_schedule_task() {
        let scheduler = Scheduler::new();
        let task = Task {
            id: 1,
            task_type: "heavy_lifting".to_string(),
            priority: 1,
            robot_id: Some("Ford".to_string()),
        };

        let result = scheduler.schedule_task(task.clone()).await;
        assert!(result.is_ok());

        let status = scheduler.get_task_status(1).await;
        assert!(status.is_some());
        assert_eq!(status.unwrap().task_type, "heavy_lifting");
    }

    #[tokio::test]
    async fn test_duplicate_task() {
        let scheduler = Scheduler::new();
        let task = Task {
            id: 1,
            task_type: "heavy_lifting".to_string(),
            priority: 1,
            robot_id: Some("Ford".to_string()),
        };

        scheduler.schedule_task(task.clone()).await.unwrap();
        let result = scheduler.schedule_task(task).await;
        assert!(result.is_err());
    }
}
```
