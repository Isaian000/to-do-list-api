"""Acceso a datos: tareas persistidas en RDS (MySQL).

Las credenciales se leen en tiempo de ejecucion desde AWS Secrets Manager
(variable DB_SECRET_NAME). Para pruebas locales se puede usar DATABASE_URL
(por ejemplo sqlite://).
"""
import json
import os
from datetime import datetime, timezone
from urllib.parse import quote_plus

import boto3
from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Integer,
    MetaData,
    String,
    Table,
    create_engine,
    insert,
    select,
    text,
)
from sqlalchemy.pool import StaticPool

metadata = MetaData()

tasks_table = Table(
    "tasks",
    metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("title", String(200), nullable=False),
    Column("done", Boolean, nullable=False, default=False),
    Column("created_at", DateTime, nullable=False),
)


def url_from_secret(secret_name: str, region: str) -> str:
    """Construye la URL de conexión a partir del secret de Secrets Manager."""
    client = boto3.client("secretsmanager", region_name=region)
    data = json.loads(client.get_secret_value(SecretId=secret_name)["SecretString"])
    return "mysql+pymysql://{user}:{pwd}@{host}:{port}/{db}".format(
        user=quote_plus(data["username"]),
        pwd=quote_plus(data["password"]),
        host=data["host"],
        port=data.get("port", 3306),
        db=data["dbname"],
    )


class Database:
    def __init__(self, url: str = None):
        self._url = url
        self._engine = None
        self._schema_ready = False

    def _resolve_url(self) -> str:
        if self._url:
            return self._url
        if os.getenv("DATABASE_URL"):
            return os.environ["DATABASE_URL"]
        secret_name = os.getenv("DB_SECRET_NAME")
        if not secret_name:
            raise RuntimeError("Define DB_SECRET_NAME (o DATABASE_URL para pruebas)")
        return url_from_secret(secret_name, os.getenv("AWS_REGION", "us-east-1"))

    @property
    def engine(self):
        # si RDS o el secret no estan listos,
        # se reintenta en la siguiente peticion.
        if self._engine is None:
            url = self._resolve_url()
            if url.startswith("sqlite"):
                self._engine = create_engine(
                    url,
                    connect_args={"check_same_thread": False},
                    poolclass=StaticPool,
                )
            else:
                self._engine = create_engine(
                    url,
                    pool_pre_ping=True,
                    pool_recycle=300,
                    connect_args={"connect_timeout": 3},
                )
        return self._engine

    def _ensure_schema(self):
        if not self._schema_ready:
            metadata.create_all(self.engine)
            self._schema_ready = True

    def ping(self) -> None:
        with self.engine.connect() as conn:
            conn.execute(text("SELECT 1"))

    def list_tasks(self) -> list:
        self._ensure_schema()
        with self.engine.connect() as conn:
            rows = conn.execute(select(tasks_table).order_by(tasks_table.c.id)).mappings()
            return [dict(r) for r in rows]

    def create_task(self, title: str, done: bool) -> dict:
        self._ensure_schema()
        now = datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)
        with self.engine.begin() as conn:
            result = conn.execute(
                insert(tasks_table).values(title=title, done=done, created_at=now)
            )
            new_id = result.inserted_primary_key[0]
            row = conn.execute(
                select(tasks_table).where(tasks_table.c.id == new_id)
            ).mappings().one()
            return dict(row)
