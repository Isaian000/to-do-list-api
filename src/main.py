"""to-do-list-api: API para gestionar tareas pendientes persistidas en RDS."""
import logging
import os
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

import metrics
from db import Database

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s"
)
logger = logging.getLogger("todo-api")

app = FastAPI(title="to-do-list-api")
database = Database()


class TaskIn(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    done: bool = False


class Task(TaskIn):
    id: int
    created_at: datetime


def app_version() -> str:
    return os.getenv("APP_VERSION", "dev")


def db_error(operation: str, exc: Exception) -> HTTPException:
    """Registra el error de RDS como metrica y devuelve un 503."""
    logger.error("Error de base de datos en %s: %s", operation, exc)
    metrics.put_metric(metrics.DATABASE_ERRORS)
    return HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail=f"Error de base de datos ({operation})",
    )


@app.get("/tasks", response_model=list[Task])
def list_tasks():
    try:
        return database.list_tasks()
    except Exception as exc:
        raise db_error("read", exc)


@app.post("/tasks", response_model=Task, status_code=status.HTTP_201_CREATED)
def create_task(task: TaskIn):
    try:
        created = database.create_task(task.title, task.done)
    except Exception as exc:
        raise db_error("write", exc)
    metrics.put_metric(metrics.TASKS_CREATED)
    return created


@app.get("/version")
def version():
    return {"version": app_version()}


@app.get("/health")
def health():
    try:
        database.ping()
        db_status = "OK"
    except Exception as exc:
        logger.error("Health check: no hay conexión a la base de datos: %s", exc)
        metrics.put_metric(metrics.DATABASE_ERRORS)
        db_status = "FAIL"

    body = {
        "status": db_status,
        "database": db_status,
        "version": app_version(),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    code = status.HTTP_200_OK if db_status == "OK" else status.HTTP_503_SERVICE_UNAVAILABLE
    return JSONResponse(status_code=code, content=body)
