```lisp
;; backend/lisp/macros.lisp
;; Purpose: Implements metaprogramming macros for MRTODP using Common Lisp (SBCL).
;; Defines macros to generate task-specific rules for task decomposition and robot
;; assignment, used by backend/lisp/planner.lisp. Ensures idempotency and safety for
;; repeated evaluation to prevent redefinition errors. Uses ASDF for package management
;; and includes robust error handling for macro expansion failures. Designed for advanced
;; users (e.g., robotics engineers) in a production environment.

;; Define ASDF system for MRTODP macros
(asdf:defsystem #:mrtodp-macros
  :description "Metaprogramming macros for MRTODP task planning"
  :depends-on ()
  :components ((:file "macros")))

;; Load required libraries
(require :asdf)

;; Define package
(defpackage #:mrtodp-macros
  (:use #:cl)
  (:export #:define-task-rule #:define-robot-assignment))
(in-package #:mrtodp-macros)

;; Macro: define-task-rule
;; Purpose: Generates a task decomposition rule for a high-level task, mapping it to
;; subtasks with priorities and required capabilities. Ensures idempotency by checking
;; if the rule already exists in *task-rules* (defined in planner.lisp).
(defmacro define-task-rule (task-name &body subtasks)
  "Define a task decomposition rule for TASK-NAME with SUBTASKS.
   Each subtask is a list of (subtask-name :priority N :capability CAP).
   Example: (define-task-rule clean-room
              (vacuum :priority 1 :capability \"heavy_lifting\")
              (dust :priority 2 :capability \"delicate_task\"))"
  (handler-case
      (let* ((task-key (intern (string-upcase task-name) :keyword))
             (subtask-list (mapcar
                            (lambda (subtask)
                              (unless (and (listp subtask)
                                           (>= (length subtask) 5)
                                           (eq (second subtask) :priority)
                                           (eq (fourth subtask) :capability))
                                (error "Invalid subtask format: ~A" subtask))
                              `(:type ,(intern (string-upcase (first subtask)) :keyword)
                                :priority ,(third subtask)
                                :capability ,(fifth subtask)))
                            subtasks)))
        ;; Check for existing rule to ensure idempotency
        `(let ((existing-rule (assoc ,task-key mrtodp-planner:*task-rules*)))
           (if existing-rule
               (format t "Warning: Task rule for ~A already exists, skipping redefinition~%" ',task-name)
               (push (cons ,task-key ',subtask-list) mrtodp-planner:*task-rules*))))
    (error (e)
      (format t "Macro expansion failed for define-task-rule ~A: ~A~%" task-name e)
      (error "Macro expansion failed: ~A" e))))

;; Macro: define-robot-assignment
;; Purpose: Generates a robot assignment rule for a task type, specifying preferred
;; robots and their capabilities. Ensures idempotency by checking for existing assignments
;; in a global *robot-assignments* parameter. Designed to interface with planner.lisp.
(defparameter *robot-assignments* nil
  "Global list of robot assignment rules: (task-type . ((robot-id . capability)...)).")

(defmacro define-robot-assignment (task-type &body robot-capabilities)
  "Define a robot assignment rule for TASK-TYPE with ROBOT-CAPABILITIES.
   Each robot-capability is a list of (robot-id capability).
   Example: (define-robot-assignment clean-room
              (Ford \"heavy_lifting\")
              (Scion \"delicate_task\"))"
  (handler-case
      (let* ((task-key (intern (string-upcase task-type) :keyword))
             (robot-list (mapcar
                          (lambda (rc)
                            (unless (and (listp rc) (= (length rc) 2))
                              (error "Invalid robot-capability format: ~A" rc))
                            `(cons ,(first rc) ,(second rc)))
                          robot-capabilities)))
        ;; Check for existing assignment to ensure idempotency
        `(let ((existing-assignment (assoc ,task-key *robot-assignments*)))
           (if existing-assignment
               (format t "Warning: Robot assignment for ~A already exists, skipping redefinition~%" ',task-type)
               (push (cons ,task-key (list ,@robot-list)) *robot-assignments*))))
    (error (e)
      (format t "Macro expansion failed for define-robot-assignment ~A: ~A~%" task-type e)
      (error "Macro expansion failed: ~A" e))))

;; Utility function to retrieve robot assignments
(defun get-robot-assignments (task-type)
  "Retrieve robot assignments for a task type."
  (handler-case
      (let ((task-key (intern (string-upcase task-type) :keyword)))
        (assoc task-key *robot-assignments*))
    (error (e)
      (format t "Failed to retrieve robot assignments for ~A: ~A~%" task-type e)
      (error "Retrieval failed: ~A" e))))

;; Example usage
(defun example-usage ()
  "Demonstrate macro usage."
  (handler-case
      (progn
        ;; Define a task rule
        (define-task-rule clean-room
          (vacuum :priority 1 :capability "heavy_lifting")
          (dust :priority 2 :capability "delicate_task")
          (navigate :priority 3 :capability "navigation"))
        (format t "Task rules: ~A~%" mrtodp-planner:*task-rules*)
        
        ;; Define a robot assignment
        (define-robot-assignment clean-room
          (Ford "heavy_lifting")
          (Scion "delicate_task"))
        (format t "Robot assignments: ~A~%" *robot-assignments*)
        
        ;; Test idempotency
        (define-task-rule clean-room
          (vacuum :priority 1 :capability "heavy_lifting"))
        (format t "After redefinition attempt, task rules: ~A~%" mrtodp-planner:*task-rules*))
    (error (e)
      (format t "Error in example-usage: ~A~%" e)
      (sb-ext:exit :code 1))))

;; Run example if executed directly
(when (equal (sb-ext:posix-argv) (list (pathname-name *load-truename*)))
  (example-usage))
```
