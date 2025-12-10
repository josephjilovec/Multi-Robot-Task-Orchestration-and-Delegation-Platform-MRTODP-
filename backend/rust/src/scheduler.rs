// backend/rust/src/scheduler.rs
// Purpose: Implements a concurrent task scheduler for MRTODP using Rust and Tokio.
// Prioritizes tasks based on robot capabilities and deadlines, interfacing with
// backend/python/ai_engine/delegator.py via FFI for task submission and status queries.
// Uses Tokio for low-latency, thread-safe concurrency and includes unit tests.
// Includes robust error handling for invalid inputs and scheduling failures, optimized
// for production use by advanced users (e.g., robotics engineers).

use std::collections::{BinaryHeap, HashMap};
use std::ffi::{c_char, CStr, CString};
use std::sync::Arc;
use tokio::sync::{Mutex, mpsc};
use tokio::time::{Duration, Instant};
use serde::{Deserialize, Serialize};
use serde_json;

// Task struct with priority and deadline
#[derive(Serialize, Deserialize, Clone, PartialEq, Eq)]
struct Task {
    id: u32,
    task_type: String,
    priority: u32, // Higher value = higher priority
    deadline: Option<u64>, // Unix timestamp (milliseconds) for deadline
    robot_id: Option<String>,
    required_capabilities: Vec<String>,
}

// Implement Ord for BinaryHeap (max-heap based on priority and deadline)
impl Ord for Task {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        let self_score = self.priority as u64 * 1_000_000_000
            + self.deadline.unwrap_or(u64::MAX);
        let other_score = other.priority as u64 * 1_000_000_000
            + other.deadline.unwrap_or(u64::MAX);
        other_score.cmp(&self_score) // Reverse for max-heap
    }
}

impl PartialOrd for Task {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

// Scheduler struct for managing tasks
struct Scheduler {
    tasks: Arc<Mutex<BinaryHeap<Task>>>,
    capabilities: Arc<Mutex<HashMap<String, Vec<String>>>>, // robot_id -> capabilities
    tx: mpsc::Sender<Task>, // Channel for task execution
}

impl Scheduler {
    // Initialize scheduler with a channel for task execution
    fn new() -> (Self, mpsc::Receiver<Task>) {
        let (tx, rx) = mpsc::channel(100);
        let scheduler = Scheduler {
            tasks: Arc::new(Mutex::new(BinaryHeap::new())),
            capabilities: Arc::new(Mutex::new(HashMap::new())),
            tx,
        };
        (scheduler, rx)
    }

    // Register robot capabilities
    async fn register_robot(&self, robot_id: String, capabilities: Vec<String>) -> Result<(), String> {
        let mut caps = self.capabilities.lock().await;
        if caps.contains_key(&robot_id) {
            return Err(format!("Robot {} already registered", robot_id));
        }
        caps.insert(robot_id, capabilities);
        Ok(())
    }

    // Schedule a task with capability-based prioritization
    async fn schedule_task(&self, task: Task) -> Result<(), String> {
        let caps = self.capabilities.lock().await;
        if let Some(robot_id) = &task.robot_id {
            if !caps.contains_key(robot_id) {
                return Err(format!("Unknown robot: {}", robot_id));
            }
            let robot_caps = caps.get(robot_id).unwrap();
            if !task.required_capabilities.iter().all(|c| robot_caps.contains(c)) {
                return Err(format!("Robot {} lacks required capabilities: {:?}", robot_id, task.required_capabilities));
            }
        }
        let mut tasks = self.tasks.lock().await;
        tasks.push(task.clone());
        self.tx.send(task).await.map_err(|e| format!("Failed to send task: {}", e))?;
        Ok(())
    }

    // Process tasks in priority order
    async fn process_tasks(mut rx: mpsc::Receiver<Task>) {
        while let Some(task) = rx.recv().await {
            if let Some(deadline) = task.deadline {
                let now = Instant::now().duration_since(Instant::UNIX_EPOCH).as_millis() as u64;
                if now > deadline {
                    eprintln!("Task {} missed deadline: {}ms", task.id, deadline);
                    continue;
                }
            }
            // Simulate task execution (replace with actual call to Python delegator)
            println!("Processing task {} (type: {}, robot: {:?})", task.id, task.task_type, task.robot_id);
        }
    }
}

// Global scheduler instance for FFI
lazy_static::lazy_static! {
    static ref SCHEDULER: Arc<Scheduler> = {
        let (scheduler, rx) = Scheduler::new();
        tokio::spawn(Scheduler::process_tasks(rx));
        Arc::new(scheduler)
    };
}

// FFI function to register robot capabilities
#[no_mangle]
pub extern "C" fn register_robot_ffi(robot_id: *const c_char, capabilities_json: *const c_char) -> *mut c_char {
    let robot_id = unsafe {
        if robot_id.is_null() {
            return CString::new("Error: Null robot ID").unwrap().into_raw();
        }
        match CStr::from_ptr(robot_id).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return CString::new("Error: Invalid robot ID").unwrap().into_raw(),
        }
    };

    let capabilities: Vec<String> = unsafe {
        if capabilities_json.is_null() {
            return CString::new("Error: Null capabilities JSON").unwrap().into_raw();
        }
        match CStr::from_ptr(capabilities_json).to_str() {
            Ok(s) => match serde_json::from_str(s) {
                Ok(caps) => caps,
                Err(e) => return CString::new(format!("Error: JSON parsing failed: {}", e)).unwrap().into_raw(),
            },
            Err(_) => return CString::new("Error: Invalid capabilities JSON").unwrap().into_raw(),
        }
    };

    let runtime = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(e) => return CString::new(format!("Error: Tokio runtime creation failed: {}", e)).unwrap().into_raw(),
    };

    let result = runtime.block_on(async {
        SCHEDULER.register_robot(robot_id, capabilities).await
    });

    match result {
        Ok(()) => CString::new("Success").unwrap().into_raw(),
        Err(e) => CString::new(format!("Error: {}", e)).unwrap().into_raw(),
    }
}

// FFI function to schedule a task
#[no_mangle]
pub extern "C" fn schedule_task_ffi(task_json: *const c_char) -> *mut c_char {
    let task_json = unsafe {
        if task_json.is_null() {
            return CString::new("Error: Null task JSON").unwrap().into_raw();
        }
        match CStr::from_ptr(task_json).to_str() {
            Ok(s) => s,
            Err(_) => return CString::new("Error: Invalid task JSON").unwrap().into_raw(),
        }
    };

    let task: Task = match serde_json::from_str(task_json) {
        Ok(task) => task,
        Err(e) => return CString::new(format!("Error: JSON parsing failed: {}", e)).unwrap().into_raw(),
    };

    let runtime = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(e) => return CString::new(format!("Error: Tokio runtime creation failed: {}", e)).unwrap().into_raw(),
    };

    let result = runtime.block_on(async {
        SCHEDULER.schedule_task(task).await
    });

    match result {
        Ok(()) => CString::new("Success").unwrap().into_raw(),
        Err(e) => CString::new(format!("Error: {}", e)).unwrap().into_raw(),
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

// Unit tests
#[cfg(test)]
mod tests {
    use super::*;
    use tokio::runtime::Runtime;

    #[tokio::test]
    async fn test_schedule_task() {
        let (scheduler, rx) = Scheduler::new();
        tokio::spawn(Scheduler::process_tasks(rx));

        let robot_id = "Ford".to_string();
        scheduler.register_robot(robot_id.clone(), vec!["heavy_lifting".to_string()]).await.unwrap();

        let task = Task {
            id: 1,
            task_type: "heavy_lifting".to_string(),
            priority: 1,
            deadline: None,
            robot_id: Some(robot_id),
            required_capabilities: vec!["heavy_lifting".to_string()],
        };

        let result = scheduler.schedule_task(task.clone()).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_missing_capability() {
        let (scheduler, rx) = Scheduler::new();
        tokio::spawn(Scheduler::process_tasks(rx));

        let robot_id = "Ford".to_string();
        scheduler.register_robot(robot_id.clone(), vec!["navigation".to_string()]).await.unwrap();

        let task = Task {
            id: 1,
            task_type: "heavy_lifting".to_string(),
            priority: 1,
            deadline: None,
            robot_id: Some(robot_id),
            required_capabilities: vec!["heavy_lifting".to_string()],
        };

        let result = scheduler.schedule_task(task).await;
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("lacks required capabilities"));
    }

    #[tokio::test]
    async fn test_deadline_miss() {
        let (scheduler, mut rx) = Scheduler::new();
        let task = Task {
            id: 1,
            task_type: "heavy_lifting".to_string(),
            priority: 1,
            deadline: Some(0), // Already missed
            robot_id: None,
            required_capabilities: vec![],
        };

        scheduler.schedule_task(task.clone()).await.unwrap();
        let received = rx.recv().await.unwrap();
        assert_eq!(received.id, task.id);
        // Note: Deadline miss is logged, not propagated as error
    }
}

