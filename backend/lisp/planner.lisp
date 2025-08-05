```lisp
;; backend/lisp/planner.lisp
;; Purpose: Implements symbolic task planning for MRTODP using Common Lisp (SBCL).
;; Provides functions to decompose high-level tasks into subtasks and generate symbolic
;; instructions for backend/python/ai_engine/delegator.py. Uses ASDF for package management
;; and SQLite for persistent task storage. Interfaces with Python components via JSON over
;; ZeroMQ. Includes robust error handling for invalid task definitions, ensuring reliability
;; for advanced users (e.g., robotics engineers) in a production environment.

;; Define ASDF system for MRTODP planner
(asdf:defsystem #:mrtodp-planner
  :description "Task planner for MRTODP"
  :depends-on (#:sqlite #:usocket #:jsown)
  :components ((:file "planner")))

;; Load required libraries
(require :asdf)
(require :sqlite)
(require :usocket)
(require :jsown)

;; Define package
(defpackage #:mrtodp-planner
  (:use #:cl #:sqlite #:usocket #:jsown)
  (:export #:decompose-task #:generate-instructions #:store-task))
(in-package #:mrtodp-planner)

;; Task decomposition rules (example; extend as needed)
(defparameter *task-rules*
  '((:clean-room . ((:vacuum :priority 1 :capability "heavy_lifting")
                    (:dust :priority 2 :capability "delicate_task")
                    (:navigate :priority 3 :capability "navigation")))
    (:assemble-part . ((:pick :priority 1 :capability "delicate_task")
                       (:place :priority 2 :capability "delicate_task")
                       (:navigate :priority 3 :capability "navigation"))))
  "Rules mapping high-level tasks to subtasks with priorities and required capabilities.")

;; SQLite database connection (global for simplicity; consider connection pooling for production)
(defparameter *db-path* "mrtodp_tasks.db"
  "Path to SQLite database for task storage.")

(defun connect-db ()
  "Connect to SQLite database, creating tasks table if it doesn't exist."
  (handler-case
      (let ((db (sqlite:connect *db-path*)))
        (sqlite:execute-non-query
         db
         "CREATE TABLE IF NOT EXISTS tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, task_type TEXT NOT NULL, subtasks TEXT, status TEXT NOT NULL, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)")
        db)
    (error (e)
      (format t "Database connection failed: ~A~%" e)
      (error "Failed to connect to database: ~A" e))))

(defun store-task (task-type subtasks status)
  "Store task and its subtasks in SQLite database."
  (handler-case
      (let ((db (connect-db))
            (subtasks-json (jsown:to-json subtasks)))
        (sqlite:execute-non-query
         db
         "INSERT INTO tasks (task_type, subtasks, status) VALUES (?, ?, ?)"
         task-type subtasks-json status)
        (sqlite:disconnect db)
        (format t "Stored task ~A with status ~A~%" task-type status))
    (error (e)
      (format t "Failed to store task ~A: ~A~%" task-type e)
      (error "Database storage failed: ~A" e))))

(defun decompose-task (task-type)
  "Decompose a high-level task into subtasks based on predefined rules.
   Returns a list of subtask plists with :type, :priority, and :capability."
  (handler-case
      (let ((rule (assoc (intern (string-upcase task-type) :keyword) *task-rules*)))
        (unless rule
          (error "Invalid task type: ~A" task-type))
        (cdr rule))
    (error (e)
      (format t "Task decomposition failed for ~A: ~A~%" task-type e)
      (error "Task decomposition failed: ~A" e))))

(defun generate-instructions (task-type)
  "Generate symbolic instructions for a task and send to Python delegator via ZeroMQ.
   Returns JSON response from delegator."
  (handler-case
      (let* ((subtasks (decompose-task task-type))
             (zmq-context (usocket:socket-connect "127.0.0.1" 5555 :protocol :stream))
             (request (jsown:new-js
                        ("task_type" task-type)
                        ("subtasks" (mapcar (lambda (subtask)
                                              (jsown:new-js
                                                ("type" (string-downcase (getf subtask :type)))
                                                ("priority" (getf subtask :priority))
                                                ("capability" (string-downcase (getf subtask :capability)))))
                                            subtasks)))))
        ;; Send request to Python delegator
        (usocket:socket-send zmq-context (jsown:to-json request))
        (let ((response (usocket:socket-receive zmq-context)))
          (unless response
            (error "No response from Python delegator"))
          (let ((parsed-response (jsown:parse response)))
            ;; Store task with subtasks
            (store-task task-type subtasks "pending")
            parsed-response)))
    (error (e)
      (format t "Instruction generation failed for ~A: ~A~%" task-type e)
      (error "Instruction generation failed: ~A" e))))

;; Example usage
(defun main ()
  "Example usage of the planner."
  (handler-case
      (progn
        (format t "Decomposing task 'clean-room'...~%")
        (let ((subtasks (decompose-task "clean-room")))
          (format t "Subtasks: ~A~%" subtasks))
        (format t "Generating instructions for 'clean-room'...~%")
        (let ((instructions (generate-instructions "clean-room")))
          (format t "Instructions: ~A~%" instructions)))
    (error (e)
      (format t "Error in main: ~A~%" e)
      (sb-ext:exit :code 1))))

;; Run main if executed directly
(when (equal (sb-ext:posix-argv) (list (pathname-name *load-truename*)))
  (main))
```
