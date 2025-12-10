# backend/elixir/marketplace/server.ex
# Purpose: Implements a concurrent skills marketplace server for MRTODP using Elixir 1.15 and Phoenix.
# Provides REST API endpoints for uploading and downloading robot skills, interfacing with
# backend/scala/marketplace/api.scala via HTTP requests. Supports concurrent skill operations
# using Elixir's actor model (GenServer) for thread-safe task management. Includes robust error
# handling for network failures, invalid inputs, and concurrency issues, targeting advanced users
# (e.g., robotics engineers, marketplace developers) in a production environment.

defmodule MRTODP.Marketplace.Server do
  use GenServer
  require Logger

  # Configuration constants
  @scala_api_url Application.compile_env(:mrtodp, :scala_api_url, "http://localhost:50053")
  @log_file "marketplace_server.log"
  @max_concurrent_tasks 10
  @skill_timeout 5000 # Timeout for skill operations (ms)

  # Skill structure
  defstruct [:id, :name, :robot_type, :code, :metadata]

  # Client API

  # Start the GenServer
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # Handle skill upload via POST /skills
  def upload_skill(conn, %{"id" => id, "name" => name, "robot_type" => robot_type, "code" => code, "metadata" => metadata}) do
    try do
      skill = %__MODULE__{id: id, name: name, robot_type: robot_type, code: code, metadata: metadata}
      case GenServer.call(__MODULE__, {:upload_skill, skill}, @skill_timeout) do
        {:ok, result} ->
          conn
          |> Plug.Conn.put_status(:created)
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(201, Jason.encode!(%{status: "success", message: "Skill uploaded", skill_id: id, result: result}))
        {:error, reason} ->
          log_error("Upload failed for skill #{id}: #{reason}")
          conn
          |> Plug.Conn.put_status(:bad_request)
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(400, Jason.encode!(%{status: "error", message: reason}))
      end
    rescue
      e ->
        log_error("Unexpected error during upload: #{inspect(e)}")
        conn
        |> Plug.Conn.put_status(:internal_server_error)
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, Jason.encode!(%{status: "error", message: "Internal server error"}))
    end
  end

  # Handle skill download via GET /skills/:id
  def download_skill(conn, %{"id" => id}) do
    try do
      case GenServer.call(__MODULE__, {:download_skill, id}, @skill_timeout) do
        {:ok, skill} ->
          conn
          |> Plug.Conn.put_status(:ok)
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(%{status: "success", skill: skill}))
        {:error, reason} ->
          log_error("Download failed for skill #{id}: #{reason}")
          conn
          |> Plug.Conn.put_status(:not_found)
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(404, Jason.encode!(%{status: "error", message: reason}))
      end
    rescue
      e ->
        log_error("Unexpected error during download: #{inspect(e)}")
        conn
        |> Plug.Conn.put_status(:internal_server_error)
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, Jason.encode!(%{status: "error", message: "Internal server error"}))
    end
  end

  # Server Callbacks (GenServer)

  # Initialize the server state
  def init(state) do
    Logger.info("Starting Marketplace Server at #{inspect(self())}")
    {:ok, state}
  end

  # Handle skill upload
  def handle_call({:upload_skill, skill}, _from, state) do
    # Check concurrent task limit
    if map_size(state) >= @max_concurrent_tasks do
      {:reply, {:error, "Too many concurrent tasks"}, state}
    else
      # Validate skill
      case validate_skill(skill) do
        :ok ->
          # Send skill to Scala API
          case send_to_scala_api(skill) do
            {:ok, result} ->
              new_state = Map.put(state, skill.id, skill)
              {:reply, {:ok, result}, new_state}
            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  # Handle skill download
  def handle_call({:download_skill, id}, _from, state) do
    case Map.get(state, id) do
      nil ->
        # Fetch from Scala API if not in local state
        case fetch_from_scala_api(id) do
          {:ok, skill_data} ->
            skill = struct(__MODULE__, skill_data)
            new_state = Map.put(state, id, skill)
            {:reply, {:ok, skill}, new_state}
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      skill ->
        {:reply, {:ok, skill}, state}
    end
  end

  # Private Functions

  # Validate skill data
  defp validate_skill(skill) do
    cond do
      skill.id == nil || skill.id == "" -> {:error, "Invalid skill ID"}
      skill.name == "" -> {:error, "Invalid skill name"}
      skill.robot_type not in ["KUKA", "ABB", "FANUC", "STAUBLI", "LUA", "CSHARP"] ->
        {:error, "Unsupported robot type: #{skill.robot_type}"}
      skill.code == "" -> {:error, "Invalid skill code"}
      true -> :ok
    end
  end

  # Send skill to Scala API
  defp send_to_scala_api(skill) do
    headers = [{"Content-Type", "application/json"}]
    body = Jason.encode!(%{
      id: skill.id,
      name: skill.name,
      robot_type: skill.robot_type,
      code: skill.code,
      metadata: skill.metadata
    })

    case HTTPoison.post("#{@scala_api_url}/marketplace/skills", body, headers, timeout: @skill_timeout) do
      {:ok, %HTTPoison.Response{status_code: 201, body: body}} ->
        {:ok, Jason.decode!(body)}
      {:ok, %HTTPoison.Response{status_code: code}} ->
        {:error, "Scala API returned status #{code}"}
      {:error, %HTTPoison.Error{reason: reason}} ->
        log_error("Failed to contact Scala API: #{inspect(reason)}")
        {:error, "Network error"}
    end
  end

  # Fetch skill from Scala API
  defp fetch_from_scala_api(id) do
    case HTTPoison.get("#{@scala_api_url}/marketplace/skills/#{id}", [], timeout: @skill_timeout) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}
      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, "Skill not found"}
      {:ok, %HTTPoison.Response{status_code: code}} ->
        {:error, "Scala API returned status #{code}"}
      {:error, %HTTPoison.Error{reason: reason}} ->
        log_error("Failed to contact Scala API: #{inspect(reason)}")
        {:error, "Network error"}
    end
  end

  # Log error to file
  defp log_error(message) do
    try do
      File.write(@log_file, "[#{DateTime.utc_now()}] ERROR: #{message}\n", [:append])
    rescue
      e -> Logger.error("Failed to log: #{inspect(e)}")
    end
  end
end

