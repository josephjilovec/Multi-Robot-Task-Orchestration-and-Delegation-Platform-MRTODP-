// backend/go/executor/executor.go
// Purpose: Implements task execution service for MRTODP using Go.
// Provides HTTP endpoints for task execution and status monitoring.

package main

import (
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/gorilla/mux"
)

type Task struct {
	ID        string    `json:"id"`
	Type      string    `json:"type"`
	RobotID   string    `json:"robot_id"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

var tasks []Task

func main() {
	r := mux.NewRouter()
	r.HandleFunc("/api/tasks", getTasks).Methods("GET")
	r.HandleFunc("/api/tasks", createTask).Methods("POST")
	r.HandleFunc("/api/tasks/{id}", getTask).Methods("GET")

	log.Println("Starting Go executor service on :50052")
	log.Fatal(http.ListenAndServe(":50052", r))
}

func getTasks(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"tasks": tasks})
}

func createTask(w http.ResponseWriter, r *http.Request) {
	var task Task
	json.NewDecoder(r.Body).Decode(&task)
	task.CreatedAt = time.Now()
	task.Status = "pending"
	tasks = append(tasks, task)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(task)
}

func getTask(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	for _, task := range tasks {
		if task.ID == vars["id"] {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(task)
			return
		}
	}
	http.NotFound(w, r)
}

