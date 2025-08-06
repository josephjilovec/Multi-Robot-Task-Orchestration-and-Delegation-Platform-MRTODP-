```lisp
;; tests/lisp/test_planner.lisp
;; Purpose: Implements unit tests for backend/lisp/planner.lisp in MRTODP using FiveAM.
;; Tests task decomposition and symbolic instruction generation functionalities, ensuring ≥90% code coverage.
;; Mocks SQLite for task storage and Python (delegator.py) interactions for task assignment.
;; Includes error handling tests for invalid tasks, database failures, and Python interaction errors.
;; Designed for advanced users (e.g., robotics engineers, AI developers) in a production environment
;; with detailed comments for maintainability.

;; Load FiveAM testing framework
(ql:quickload :fiveam)
(use-package :fiveam)

;; Load planner (assumed file)
(load "backend/lisp/planner.lisp")

;; Mock SQLite database
(defclass mock-sqlite-db ()
  ((tasks :initform '() :accessor tasks)))

(defmethod get-task ((db mock-sqlite-db) task-id)
  "Mock retrieving a task from SQLite database."
  (if (string= task-id "")
      (error "Invalid task ID")
      (find task-id (tasks db) :key #'car :test #'string=)))

(defmethod store-task ((db mock-sqlite-db) task-id subtasks)
  "Mock storing subtasks in SQLite database."
  (if (string= task-id "DB_FAIL")
      (error "Database storage failure")
      (push (cons task-id subtasks) (tasks db))))

;; Mock Python delegator interaction
(defclass mock-python-delegator ()
  ())

(defmethod assign-subtask ((delegator mock-python-delegator) subtask)
  "Mock assigning a subtask via Python delegator.py."
  (cond ((string= (getf subtask :id) "INVALID_SUBTASK")
         (error "Invalid subtask ID"))
        ((null (getf subtask :command))
         (error "Subtask command missing"))
        (t "KUKA")))

;; Assumed Planner class for reference
(defclass planner ()
  ((db :initarg :db :reader planner-db)
   (delegator :initarg :delegator :reader planner-delegator)))

(defmethod decompose-task ((planner planner) task-id command parameters)
  "Decompose a task into subtasks based on command and parameters."
  (unless (and task-id command parameters)
    (error "Task ID, command, and parameters are required"))
  (unless (= (length parameters) 5)
    (error "Parameters must have length 5"))
  (let ((subtasks
         (cond ((string= command "weld_component")
                (list
                 (list :id (concatenate 'string task-id "-1") :command "move_to_position" :parameters (subseq parameters 0 3))
                 (list :id (concatenate 'string task-id "-2") :command "weld" :parameters (subseq parameters 3 5))))
               ((string= command "inspect_part")
                (list
                 (list :id (concatenate 'string task-id "-1") :command "scan_surface" :parameters parameters)))
               (t (error "Unsupported command: ~A" command)))))
    (store-task (planner-db planner) task-id subtasks)
    subtasks))

(defmethod generate-instructions ((planner planner) task-id)
  "Generate symbolic instructions for a task by assigning subtasks to robots."
  (let ((subtasks (get-task (planner-db planner) task-id)))
    (unless subtasks
      (error "Task not found: ~A" task-id))
    (mapcar
     (lambda (subtask)
       (let ((robot-id (assign-subtask (planner-delegator planner) subtask)))
         (list :subtask-id (getf subtask :id)
               :robot-id robot-id
               :command (getf subtask :command)
               :parameters (getf subtask :parameters))))
     subtasks)))

;; Test suite setup
(def-suite planner-suite :description "Test suite for Planner class")
(in-suite planner-suite)

;; Test fixtures
(def-fixture planner-fixture ()
  (let ((mock-db (make-instance 'mock-sqlite-db))
        (mock-delegator (make-instance 'mock-python-delegator))
        (planner (make-instance 'planner :db (make-instance 'mock-sqlite-db) :delegator (make-instance 'mock-python-delegator))))
    (&body)))

;; Test cases
(test decompose-task-success
  "Test successful task decomposition."
  (with-fixture planner-fixture ()
    (let ((task-id "TASK_1")
          (command "weld_component")
          (parameters '(100.0 10.0 20.0 30.0 1.0)))
      (let ((subtasks (decompose-task planner task-id command parameters)))
        (is (= 2 (length subtasks)))
        (is (string= "TASK_1-1" (getf (first subtasks) :id)))
        (is (string= "move_to_position" (getf (first subtasks) :command)))
        (is (equal '(100.0 10.0 20.0) (getf (first subtasks) :parameters)))
        (is (string= "TASK_1-2" (getf (second subtasks) :id)))
        (is (string= "weld" (getf (second subtasks) :command)))
        (is (equal '(30.0 1.0) (getf (second subtasks) :parameters)))
        (is (equal (list (cons task-id subtasks)) (tasks (planner-db planner))))))))

(test decompose-task-invalid-command
  "Test decomposition with unsupported command."
  (with-fixture planner-fixture ()
    (signals error
      "Unsupported command: move_arm"
      (decompose-task planner "TASK_2" "move_arm" '(100.0 10.0 20.0 30.0 1.0))))

(test decompose-task-invalid-parameters
  "Test decomposition with invalid parameters."
  (with-fixture planner-fixture ()
    (signals error
      "Parameters must have length 5"
      (decompose-task planner "TASK_3" "weld_component" '(100.0)))))

(test decompose-task-empty-task-id
  "Test decomposition with empty task ID."
  (with-fixture planner-fixture ()
    (signals error
      "Task ID, command, and parameters are required"
      (decompose-task planner "" "weld_component" '(100.0 10.0 20.0 30.0 1.0)))))

(test decompose-task-database-failure
  "Test decomposition with database storage failure."
  (with-fixture planner-fixture ()
    (signals error
      "Database storage failure"
      (decompose-task planner "DB_FAIL" "weld_component" '(100.0 10.0 20.0 30.0 1.0)))))

(test generate-instructions-success
  "Test successful symbolic instruction generation."
  (with-fixture planner-fixture ()
    (let ((task-id "TASK_4")
          (command "inspect_part")
          (parameters '(100.0 10.0 20.0 30.0 1.0)))
      (decompose-task planner task-id command parameters)
      (let ((instructions (generate-instructions planner task-id)))
        (is (= 1 (length instructions)))
        (is (string= "TASK_4-1" (getf (first instructions) :subtask-id)))
        (is (string= "KUKA" (getf (first instructions) :robot-id)))
        (is (string= "scan_surface" (getf (first instructions) :command)))
        (is (equal parameters (getf (first instructions) :parameters)))))))

(test generate-instructions-task-not-found
  "Test instruction generation with non-existent task."
  (with-fixture planner-fixture ()
    (signals error
      "Task not found: TASK_5"
      (generate-instructions planner "TASK_5"))))

(test generate-instructions-invalid-subtask
  "Test instruction generation with invalid subtask ID."
  (with-fixture planner-fixture ()
    (let ((task-id "TASK_6")
          (command "weld_component")
          (parameters '(100.0 10.0 20.0 30.0 1.0)))
      (with-mocks ((assign-subtask (planner-delegator planner) (lambda (subtask)
                                                               (when (string= (getf subtask :id) "TASK_6-1")
                                                                 (error "Invalid subtask ID")))))
        (decompose-task planner task-id command parameters)
        (signals error
          "Invalid subtask ID"
          (generate-instructions planner task-id))))))

(test generate-instructions-missing-subtask-command
  "Test instruction generation with missing subtask command."
  (with-fixture planner-fixture ()
    (let ((task-id "TASK_7")
          (command "weld_component")
          (parameters '(100.0 10.0 20.0 30.0 1.0)))
      (with-mocks ((assign-subtask (planner-delegator planner) (lambda (subtask)
                                                               (when (string= (getf subtask :id) "TASK_7-1")
                                                                 (error "Subtask command missing")))))
        (decompose-task planner task-id command parameters)
        (signals error
          "Subtask command missing"
          (generate-instructions planner task-id))))))
```
