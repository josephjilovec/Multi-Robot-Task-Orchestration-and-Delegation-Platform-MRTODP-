// backend/scala/marketplace/api.scala
// Purpose: Implements a REST API for the MRTODP skills marketplace using Scala 3 and Akka HTTP.
// Provides endpoints for uploading, downloading, and searching skills, interfacing with SQLite
// for skill storage and backend/elixir/marketplace/ via HTTP for concurrent skill processing.
// Includes robust error handling for API failures, ensuring reliability for advanced users
// (e.g., robotics engineers, marketplace developers) in a production environment.

import akka.actor.typed.ActorSystem
import akka.actor.typed.scaladsl.Behaviors
import akka.http.scaladsl.Http
import akka.http.scaladsl.model.{ContentTypes, HttpEntity, HttpMethods, HttpRequest, StatusCodes}
import akka.http.scaladsl.server.Directives._
import akka.http.scaladsl.server.Route
import de.heikoseeberger.akkahttpcirce.CirceSupport._
import io.circe.generic.auto._
import io.circe.syntax._
import slick.jdbc.SQLiteProfile.api._
import slick.lifted.ProvenShape
import scala.concurrent.{ExecutionContext, Future}
import scala.util.{Failure, Success}
import java.util.logging.{Level, Logger}
import scala.concurrent.duration._

// Case classes for API payloads
case class Skill(id: Option[Int], name: String, taskType: String, description: String, robotId: String)
case class SearchQuery(taskType: Option[String], robotId: Option[String])
case class ApiResponse(status: String, message: Option[String], data: Option[Any] = None)

// Slick table definition for skills
class SkillsTable(tag: Tag) extends Table[Skill](tag, "skills") {
  def id: Rep[Int] = column[Int]("id", O.PrimaryKey, O.AutoInc)
  def name: Rep[String] = column[String]("name")
  def taskType: Rep[String] = column[String]("task_type")
  def description: Rep[String] = column[String]("description")
  def robotId: Rep[String] = column[String]("robot_id")
  def * : ProvenShape[Skill] = (id.?, name, taskType, description, robotId) <> (Skill.tupled, Skill.unapply)
}

object MarketplaceApi {
  // Logger for debugging and error tracking
  private val logger: Logger = Logger.getLogger(this.getClass.getName)

  // SQLite database configuration
  private val db: Database = Database.forConfig("sqlite")
  private val skills: TableQuery[SkillsTable] = TableQuery[SkillsTable]

  // Initialize database schema
  private def initSchema()(implicit ec: ExecutionContext): Future[Unit] = {
    db.run(skills.schema.createIfNotExists).map { _ =>
      logger.info("Initialized skills table schema")
    }.recover {
      case e: Exception =>
        logger.log(Level.SEVERE, s"Failed to initialize database schema: ${e.getMessage}")
        throw new RuntimeException(s"Database schema initialization failed: ${e.getMessage}")
    }
  }

  // Interface with Elixir marketplace via HTTP
  private def callElixirMarketplace(endpoint: String, payload: String)(implicit system: ActorSystem[_]): Future[String] = {
    Http()(system).singleRequest(HttpRequest(
      method = HttpMethods.POST,
      uri = s"http://localhost:4000$endpoint",
      entity = HttpEntity(ContentTypes.`application/json`, payload)
    )).flatMap { response =>
      response.entity.toStrict(5.seconds)(system.executionContext).map(_.data.utf8String)
    }.recover {
      case e: Exception =>
        logger.log(Level.SEVERE, s"Elixir marketplace call failed: ${e.getMessage}")
        throw new RuntimeException(s"Elixir marketplace communication failed: ${e.getMessage}")
    }
  }

  // API routes
  def routes(implicit system: ActorSystem[_]): Route = {
    implicit val ec: ExecutionContext = system.executionContext

    // Initialize database schema on startup
    initSchema()

    pathPrefix("api" / "skills") {
      concat(
        // Endpoint: POST /api/skills/upload
        path("upload") {
          post {
            entity(as[Skill]) { skill =>
              onComplete(uploadSkill(skill)) {
                case Success(result) =>
                  complete(StatusCodes.OK, result.asJson)
                case Failure(e) =>
                  logger.log(Level.WARNING, s"Upload failed: ${e.getMessage}")
                  complete(StatusCodes.InternalServerError, ApiResponse("error", Some(e.getMessage)).asJson)
              }
            }
          }
        },
        // Endpoint: GET /api/skills/download/:id
        path("download" / IntNumber) { id =>
          get {
            onComplete(downloadSkill(id)) {
              case Success(Some(skill)) =>
                complete(StatusCodes.OK, ApiResponse("success", None, Some(skill)).asJson)
              case Success(None) =>
                complete(StatusCodes.NotFound, ApiResponse("error", Some(s"Skill $id not found")).asJson)
              case Failure(e) =>
                logger.log(Level.WARNING, s"Download failed: ${e.getMessage}")
                complete(StatusCodes.InternalServerError, ApiResponse("error", Some(e.getMessage)).asJson)
            }
          }
        },
        // Endpoint: POST /api/skills/search
        path("search") {
          post {
            entity(as[SearchQuery]) { query =>
              onComplete(searchSkills(query)) {
                case Success(skills) =>
                  complete(StatusCodes.OK, ApiResponse("success", None, Some(skills)).asJson)
                case Failure(e) =>
                  logger.log(Level.WARNING, s"Search failed: ${e.getMessage}")
                  complete(StatusCodes.InternalServerError, ApiResponse("error", Some(e.getMessage)).asJson)
              }
            }
          }
        }
      )
    }
  }

  // Upload a skill to the database and notify Elixir marketplace
  private def uploadSkill(skill: Skill)(implicit ec: ExecutionContext): Future[ApiResponse] = {
    val insertQuery = (skills returning skills.map(_.id) into ((skill, id) => skill.copy(id = Some(id)))) += skill
    db.run(insertQuery).flatMap { insertedSkill =>
      // Notify Elixir marketplace for concurrent processing (optional)
      callElixirMarketplace("/skills/process", insertedSkill.asJson.toString).map { _ =>
        logger.info(s"Uploaded skill ${insertedSkill.name} with ID ${insertedSkill.id.get}")
        ApiResponse("success", None, Some(insertedSkill))
      }.recover {
        case e: Exception =>
          logger.warning(s"Elixir notification failed, but skill uploaded: ${e.getMessage}")
          ApiResponse("success", None, Some(insertedSkill))
      }
    }.recover {
      case e: Exception =>
        logger.log(Level.SEVERE, s"Skill upload failed: ${e.getMessage}")
        throw new RuntimeException(s"Skill upload failed: ${e.getMessage}")
    }
  }

  // Download a skill by ID from the database
  private def downloadSkill(id: Int)(implicit ec: ExecutionContext): Future[Option[Skill]] = {
    val query = skills.filter(_.id === id).result.headOption
    db.run(query).map { result =>
      result match {
        case Some(skill) =>
          logger.info(s"Downloaded skill ID $id")
          Some(skill)
        case None =>
          logger.warning(s"Skill ID $id not found")
          None
      }
    }.recover {
      case e: Exception =>
        logger.log(Level.SEVERE, s"Skill download failed: ${e.getMessage}")
        throw new RuntimeException(s"Skill download failed: ${e.getMessage}")
    }
  }

  // Search skills by task type or robot ID
  private def searchSkills(query: SearchQuery)(implicit ec: ExecutionContext): Future[Seq[Skill]] = {
    val baseQuery = skills.result
    val filteredQuery = (query.taskType, query.robotId) match {
      case (Some(taskType), Some(robotId)) =>
        skills.filter(s => s.taskType === taskType && s.robotId === robotId).result
      case (Some(taskType), None) =>
        skills.filter(_.taskType === taskType).result
      case (None, Some(robotId)) =>
        skills.filter(_.robotId === robotId).result
      case (None, None) =>
        baseQuery
    }
    db.run(filteredQuery).map { results =>
      logger.info(s"Found ${results.length} skills for query: $query")
      results
    }.recover {
      case e: Exception =>
        logger.log(Level.SEVERE, s"Skill search failed: ${e.getMessage}")
        throw new RuntimeException(s"Skill search failed: ${e.getMessage}")
    }
  }

  // Main entry point
  def main(args: Array[String]): Unit = {
    implicit val system: ActorSystem[Nothing] = ActorSystem(Behaviors.empty, "MarketplaceApi")
    implicit val ec: ExecutionContext = system.executionContext

    Http().newServerAt("0.0.0.0", 8080).bind(routes).onComplete {
      case Success(binding) =>
        logger.info(s"Marketplace API started at ${binding.localAddress}")
      case Failure(e) =>
        logger.log(Level.SEVERE, s"Failed to start API server: ${e.getMessage}")
        system.terminate()
    }
  }
}

