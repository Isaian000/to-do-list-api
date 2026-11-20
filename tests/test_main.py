import pytest
from fastapi.testclient import TestClient
from sqlalchemy.exc import OperationalError

import main
from db import Database


class BrokenDatabase:
    """Simula una instancia de RDS detenida."""

    def _fail(self, *args, **kwargs):
        raise OperationalError("SELECT 1", {}, Exception("RDS no disponible"))

    ping = list_tasks = create_task = _fail


@pytest.fixture
def published(monkeypatch):
    calls = []
    monkeypatch.setattr(
        main.metrics, "put_metric", lambda name, value=1.0, unit="Count": calls.append(name)
    )
    return calls


@pytest.fixture
def client(monkeypatch, published):
    monkeypatch.setattr(main, "database", Database("sqlite://"))
    return TestClient(main.app)


@pytest.fixture
def broken_client(monkeypatch, published):
    monkeypatch.setattr(main, "database", BrokenDatabase())
    return TestClient(main.app)


def test_version_reads_env_var(client, monkeypatch):
    monkeypatch.setenv("APP_VERSION", "v9.9.9")
    resp = client.get("/version")
    assert resp.status_code == 200
    assert resp.json() == {"version": "v9.9.9"}


def test_create_and_list_tasks(client, published):
    resp = client.post("/tasks", json={"title": "estudiar para el examen", "done": False})
    assert resp.status_code == 201
    created = resp.json()
    assert created["id"] == 1
    assert created["title"] == "estudiar para el examen"
    assert created["done"] is False

    client.post("/tasks", json={"title": "entregar práctica 4", "done": True})

    tasks = client.get("/tasks").json()
    assert [t["title"] for t in tasks] == ["estudiar para el examen", "entregar práctica 4"]
    assert published.count("TasksCreated") == 2


def test_create_task_rejects_empty_title(client):
    resp = client.post("/tasks", json={"title": "", "done": False})
    assert resp.status_code == 422


def test_health_ok(client, monkeypatch):
    monkeypatch.setenv("APP_VERSION", "v1.0.0")
    resp = client.get("/health")
    body = resp.json()
    assert resp.status_code == 200
    assert body["database"] == "OK"
    assert body["version"] == "v1.0.0"
    assert "timestamp" in body


def test_health_fail_reports_db_error_metric(broken_client, published):
    resp = broken_client.get("/health")
    assert resp.status_code == 503
    assert resp.json()["database"] == "FAIL"
    assert published == ["DatabaseErrors"]


def test_read_and_write_errors_return_503_and_count(broken_client, published):
    assert broken_client.get("/tasks").status_code == 503
    assert broken_client.post("/tasks", json={"title": "x"}).status_code == 503
    assert published == ["DatabaseErrors", "DatabaseErrors"]
