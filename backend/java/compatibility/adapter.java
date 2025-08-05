```java
// backend/java/compatibility/adapter.java
// Purpose: Implements a compatibility layer for MRTODP using Java 21 to translate skills
// downloaded from backend/scala/marketplace/api.scala into robot-specific formats (e.g., KRL, RAPID).
// Interfaces with backend/cpp/robot_interface/ via HTTP for skill execution on robots.
// Includes robust error handling for format mismatches and invalid inputs, ensuring reliability
// for advanced users (e.g., robotics engineers) in a production environment.

package com.mrtodp.compatibility;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.HashMap;
import java.util.Map;
import java.util.logging.Logger;
import java.util.logging.Level;

// Skill representation from Scala marketplace
record Skill(int id, String name, String taskType, String description, String robotId) {}

// Response from Scala marketplace API
record ApiResponse(String status, String message, Object data) {}

// Robot-specific command format
record RobotCommand(String robotId, String format, String command) {}

// Adapter interface for skill translation
interface SkillAdapter {
    RobotCommand translate(Skill skill) throws CompatibilityException;
}

// Exception for compatibility errors
class CompatibilityException extends Exception {
    public CompatibilityException(String message) {
        super(message);
    }
    public CompatibilityException(String message, Throwable cause) {
        super(message, cause);
    }
}

// KRL adapter for KUKA robots
class KRLAdapter implements SkillAdapter {
    private static final Logger LOGGER = Logger.getLogger(KRLAdapter.class.getName());

    @Override
    public RobotCommand translate(Skill skill) throws CompatibilityException {
        try {
            if (!"KRL".equalsIgnoreCase(skill.robotId())) {
                throw new CompatibilityException("KRL adapter requires robotId 'KRL', got: " + skill.robotId());
            }
            String command = String.format("DEF %s()\n  ; Task: %s\n  ; Description: %s\nEND", 
                skill.name(), skill.taskType(), skill.description());
            LOGGER.info("Translated skill %s to KRL format for robot %s".formatted(skill.name(), skill.robotId()));
            return new RobotCommand(skill.robotId(), "KRL", command);
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "KRL translation failed for skill %s: %s".formatted(skill.name(), e.getMessage()), e);
            throw new CompatibilityException("KRL translation failed: " + e.getMessage(), e);
        }
    }
}

// RAPID adapter for ABB robots
class RAPIDAdapter implements SkillAdapter {
    private static final Logger LOGGER = Logger.getLogger(RAPIDAdapter.class.getName());

    @Override
    public RobotCommand translate(Skill skill) throws CompatibilityException {
        try {
            if (!"RAPID".equalsIgnoreCase(skill.robotId())) {
                throw new CompatibilityException("RAPID adapter requires robotId 'RAPID', got: " + skill.robotId());
            }
            String command = String.format("PROC %s()\n  ! Task: %s\n  ! Description: %s\nENDPROC", 
                skill.name(), skill.taskType(), skill.description());
            LOGGER.info("Translated skill %s to RAPID format for robot %s".formatted(skill.name(), skill.robotId()));
            return new RobotCommand(skill.robotId(), "RAPID", command);
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "RAPID translation failed for skill %s: %s".formatted(skill.name(), e.getMessage()), e);
            throw new CompatibilityException("RAPID translation failed: " + e.getMessage(), e);
        }
    }
}

// Main adapter class
public class SkillCompatibilityAdapter {
    private static final Logger LOGGER = Logger.getLogger(SkillCompatibilityAdapter.class.getName());
    private final HttpClient client;
    private final String marketplaceUrl;
    private final String robotInterfaceUrl;
    private final ObjectMapper mapper;
    private final Map<String, SkillAdapter> adapters;

    public SkillCompatibilityAdapter(String marketplaceUrl, String robotInterfaceUrl) {
        this.client = HttpClient.newBuilder().connectTimeout(java.time.Duration.ofSeconds(10)).build();
        this.marketplaceUrl = marketplaceUrl;
        this.robotInterfaceUrl = robotInterfaceUrl;
        this.mapper = new ObjectMapper();
        this.adapters = new HashMap<>();
        this.adapters.put("KRL", new KRLAdapter());
        this.adapters.put("RAPID", new RAPIDAdapter());
        LOGGER.info("Initialized SkillCompatibilityAdapter with marketplace URL: %s and robot interface URL: %s"
            .formatted(marketplaceUrl, robotInterfaceUrl));
    }

    // Download skill from Scala marketplace
    public Skill downloadSkill(int skillId) throws CompatibilityException {
        try {
            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create("%s/api/skills/download/%d".formatted(marketplaceUrl, skillId)))
                .GET()
                .build();
            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() != 200) {
                throw new CompatibilityException("Unexpected status code: " + response.statusCode());
            }

            ApiResponse apiResponse = mapper.readValue(response.body(), ApiResponse.class);
            if (!"success".equals(apiResponse.status())) {
                throw new CompatibilityException("API error: " + apiResponse.message());
            }

            Skill skill = mapper.convertValue(apiResponse.data(), Skill.class);
            LOGGER.info("Downloaded skill %s (ID: %d) for robot %s".formatted(skill.name(), skill.id(), skill.robotId()));
            return skill;
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Failed to download skill %d: %s".formatted(skillId, e.getMessage()), e);
            throw new CompatibilityException("Skill download failed: " + e.getMessage(), e);
        }
    }

    // Translate skill to robot-specific format
    public RobotCommand translateSkill(Skill skill) throws CompatibilityException {
        try {
            String format = skill.robotId().toUpperCase();
            SkillAdapter adapter = adapters.get(format);
            if (adapter == null) {
                throw new CompatibilityException("No adapter found for format: " + format);
            }
            return adapter.translate(skill);
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Skill translation failed for %s: %s".formatted(skill.name(), e.getMessage()), e);
            throw new CompatibilityException("Skill translation failed: " + e.getMessage(), e);
        }
    }

    // Execute skill via robot interface
    public void executeSkill(RobotCommand command) throws CompatibilityException {
        try {
            String json = mapper.writeValueAsString(command);
            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create("%s/robot/execute".formatted(robotInterfaceUrl)))
                .POST(HttpRequest.BodyPublishers.ofString(json))
                .header("Content-Type", "application/json")
                .build();
            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() != 200) {
                throw new CompatibilityException("Unexpected status code: " + response.statusCode());
            }

            Map<String, String> result = mapper.readValue(response.body(), Map.class);
            if (!"success".equals(result.get("status"))) {
                throw new CompatibilityException("Execution failed: " + result.get("message"));
            }

            LOGGER.info("Successfully executed command for robot %s in %s format".formatted(command.robotId(), command.format()));
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Skill execution failed for robot %s: %s".formatted(command.robotId(), e.getMessage()), e);
            throw new CompatibilityException("Skill execution failed: " + e.getMessage(), e);
        }
    }

    // Process a skill from download to execution
    public void processSkill(int skillId) throws CompatibilityException {
        Skill skill = downloadSkill(skillId);
        RobotCommand command = translateSkill(skill);
        executeSkill(command);
    }
}
```
