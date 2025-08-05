```ada
-- backend/ada/safety/safety.adb
-- Purpose: Implements safety-critical components for MRTODP using Ada 2012.
-- Validates task inputs from backend/cpp/task_manager/ via JSON file exchange to
-- ensure safe task execution (e.g., "weld_component"). Includes robust error handling
-- for invalid inputs, JSON parsing errors, and file I/O issues, ensuring reliability
-- for safety-critical operations. Targets advanced users (e.g., robotics engineers)
-- in a production environment.

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Float_Text_IO; use Ada.Float_Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with GNATCOLL.JSON; use GNATCOLL.JSON;

procedure Safety is
   -- Constants
   Max_Velocity : constant Float := 500.0;  -- Maximum velocity (mm/s)
   Max_Position : constant Float := 1000.0; -- Maximum position coordinate (mm)
   Input_File   : constant String := "tasks.json";
   Output_File  : constant String := "safety_check.json";
   Log_File     : constant String := "safety.log";

   -- Task record for validation
   type Task_Record is record
      Task_ID   : Integer;
      Robot_ID  : Unbounded_String;
      Command   : Unbounded_String;
      Velocity  : Float;
      Position  : array (1 .. 3) of Float; -- X, Y, Z
      Tool_Active : Boolean;
   end record;

   -- Safety check result
   type Safety_Result is record
      Is_Safe   : Boolean;
      Message   : Unbounded_String;
   end record;

   -- Log message to file
   procedure Log (Message : String) is
      File : File_Type;
   begin
      begin
         Open (File, Append_File, Log_File);
      exception
         when Name_Error =>
            Create (File, Out_File, Log_File);
      end;
      Put_Line (File, "[" & Ada.Calendar.Clock'Image & "] " & Message);
      Close (File);
   exception
      when others =>
         Put_Line (Standard_Error, "Warning: Failed to log: " & Message);
   end Log;

   -- Parse JSON tasks from file
   function Parse_Tasks (File_Name : String) return Task_Record is
      JSON_Data : JSON_Value;
      Task_JSON : JSON_Value;
      Task      : Task_Record;
   begin
      begin
         JSON_Data := Read (File_Name);
         Task_JSON := JSON_Data.Get ("tasks").Get (1); -- Assume single task for simplicity
         Task.Task_ID := Task_JSON.Get ("id");
         Task.Robot_ID := To_Unbounded_String (Task_JSON.Get ("robotId"));
         Task.Command := To_Unbounded_String (Task_JSON.Get ("command"));
         Task.Velocity := Float (Task_JSON.Get ("parameters").Get (1));
         Task.Position (1) := Float (Task_JSON.Get ("parameters").Get (2));
         Task.Position (2) := Float (Task_JSON.Get ("parameters").Get (3));
         Task.Position (3) := Float (Task_JSON.Get ("parameters").Get (4));
         Task.Tool_Active := Float (Task_JSON.Get ("parameters").Get (5)) > 0.0;
         Log ("Parsed task ID " & Task.Task_ID'Image);
         return Task;
      exception
         when Constraint_Error =>
            Log ("Invalid JSON structure in " & File_Name);
            raise Constraint_Error with "Invalid JSON structure";
         when others =>
            Log ("Error parsing " & File_Name);
            raise;
      end;
   end Parse_Tasks;

   -- Validate task for safety
   function Validate_Task (Task : Task_Record) return Safety_Result is
      Result : Safety_Result := (Is_Safe => True, Message => To_Unbounded_String ("Task is safe"));
   begin
      -- Validate command
      if Task.Command /= "weld_component" then
         Result.Is_Safe := False;
         Result.Message := To_Unbounded_String ("Unsupported command: " & To_String (Task.Command));
         return Result;
      end if;

      -- Validate velocity
      if Task.Velocity <= 0.0 or Task.Velocity > Max_Velocity then
         Result.Is_Safe := False;
         Result.Message := To_Unbounded_String ("Invalid velocity: " & Task.Velocity'Image);
         return Result;
      end if;

      -- Validate position
      for I in Task.Position'Range loop
         if abs (Task.Position (I)) > Max_Position then
            Result.Is_Safe := False;
            Result.Message := To_Unbounded_String ("Invalid position coordinate " & I'Image & ": " & Task.Position (I)'Image);
            return Result;
         end if;
      end loop;

      -- Validate robot ID
      if Length (Task.Robot_ID) = 0 then
         Result.Is_Safe := False;
         Result.Message := To_Unbounded_String ("Invalid robot ID");
         return Result;
      end if;

      return Result;
   exception
      when others =>
         Log ("Error validating task ID " & Task.Task_ID'Image);
         return (Is_Safe => False, Message => To_Unbounded_String ("Validation error"));
   end Validate_Task;

   -- Write safety result to JSON file
   procedure Write_Result (Result : Safety_Result; File_Name : String) is
      JSON_Result : JSON_Value := Create_Object;
      File : File_Type;
   begin
      Set_Field (JSON_Result, "isSafe", Result.Is_Safe);
      Set_Field (JSON_Result, "message", To_String (Result.Message));
      begin
         Create (File, Out_File, File_Name);
         Write (File, JSON_Result.Write);
         Close (File);
         Log ("Wrote safety result to " & File_Name);
      exception
         when others =>
            Log ("Error writing result to " & File_Name);
            raise;
      end;
   end Write_Result;

   -- Main procedure
   Task : Task_Record;
   Result : Safety_Result;
begin
   Log ("Starting safety validation...");
   begin
      if not Ada.Directories.Exists (Input_File) then
         Log ("Input file not found: " & Input_File);
         raise Name_Error with "Input file not found";
      end if;

      Task := Parse_Tasks (Input_File);
      Result := Validate_Task (Task);
      Write_Result (Result, Output_File);

      if Result.Is_Safe then
         Log ("Task ID " & Task.Task_ID'Image & " is safe");
      else
         Log ("Task ID " & Task.Task_ID'Image & " failed safety check: " & To_String (Result.Message));
      end if;
   exception
      when Name_Error =>
         Log ("Fatal error: Input file not found");
      when Constraint_Error =>
         Log ("Fatal error: Invalid JSON structure");
      when others =>
         Log ("Fatal error: Unexpected issue during validation");
         raise;
   end;
   Log ("Safety validation completed");
end Safety;
```
