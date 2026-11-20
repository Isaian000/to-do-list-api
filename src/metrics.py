"""Métricas personalizadas en CloudWatch con put_metric_data (boto3).

Solo se publican si METRICS_ENABLED=true (en la EC2). En pruebas y en local
quedan desactivadas para no requerir credenciales de AWS.
"""
import logging
import os
from functools import lru_cache

import boto3
from botocore.config import Config

logger = logging.getLogger("todo-api.metrics")

NAMESPACE = os.getenv("METRICS_NAMESPACE", "TodoApi")
SERVICE = "todo-api"

# Nombres de las métricas instrumentadas
DATABASE_ERRORS = "DatabaseErrors"
TASKS_CREATED = "TasksCreated"


def enabled() -> bool:
    return os.getenv("METRICS_ENABLED", "false").lower() == "true"


@lru_cache(maxsize=1)
def _client():
    return boto3.client(
        "cloudwatch",
        region_name=os.getenv("AWS_REGION", "us-east-1"),
        config=Config(connect_timeout=2, read_timeout=2, retries={"max_attempts": 2}),
    )


def put_metric(name: str, value: float = 1.0, unit: str = "Count") -> None:
    if not enabled():
        logger.debug("metric %s=%s (deshabilitada)", name, value)
        return
    try:
        _client().put_metric_data(
            Namespace=NAMESPACE,
            MetricData=[
                {
                    "MetricName": name,
                    "Dimensions": [{"Name": "Service", "Value": SERVICE}],
                    "Value": value,
                    "Unit": unit,
                }
            ],
        )
    except Exception:  # nunca tumbar la petición por una métrica
        logger.exception("No se pudo publicar la métrica %s", name)
