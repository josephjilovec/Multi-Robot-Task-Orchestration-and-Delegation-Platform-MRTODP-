// backend/java/compatibility/adapter.java
// Purpose: Java compatibility adapter for MRTODP
// Provides integration layer for Java-based robot systems

package com.mrtodp.compatibility;

import com.google.gson.Gson;
import spark.Spark;

public class Adapter {
    private static Gson gson = new Gson();

    public static void main(String[] args) {
        Spark.port(50053);
        
        Spark.get("/api/health", (req, res) -> {
            res.type("application/json");
            return gson.toJson(new HealthResponse("ok"));
        });

        Spark.post("/api/tasks", (req, res) -> {
            res.type("application/json");
            Task task = gson.fromJson(req.body(), Task.class);
            return gson.toJson(task);
        });
    }

    static class HealthResponse {
        String status;
        HealthResponse(String status) {
            this.status = status;
        }
    }

    static class Task {
        String id;
        String type;
        String robotId;
    }
}

