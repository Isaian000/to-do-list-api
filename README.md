# to-do-list-api — Práctica 4 (CI/CD + Observabilidad)

API de tareas pendientes en **FastAPI**, persistida en **RDS MySQL**, con credenciales en
**Secrets Manager**, infraestructura en **Terraform** (estado remoto en S3), pipeline de
**GitHub Actions** y observabilidad en **CloudWatch**.

## Endpoints

| Endpoint | Descripción |
|---|---|
| `GET /tasks` | Lista de tareas registradas |
| `POST /tasks` | Crea una tarea (`{"title": "...", "done": false}`) |
| `GET /version` | Versión desplegada (variable de ambiente `APP_VERSION`) |
| `GET /health` | Conexión a la BD (`OK`/`FAIL`), versión y timestamp del servidor |

```bash
curl -X POST http://<ip-ec2>:8000/tasks -H "Content-Type: application/json" \
  -d '{"title": "estudiar para el examen de desarrollo en la nube", "done": false}'
curl http://<ip-ec2>:8000/tasks
```

## Estructura

```
src/            main.py (API), db.py (RDS + Secrets Manager), metrics.py (put_metric_data)
tests/          pruebas unitarias (pytest, SQLite en memoria + BD simulada caída)
terraform/      main.tf, variables.tf, outputs.tf, user_data.sh.tftpl
alerting/       alarms.json y cloudwatch-dashboard.json (Terraform los lee)
scripts/        deploy_remote.sh (se ejecuta en la EC2 durante el deploy)
.github/workflows/
  ci.yml            PR a main → pruebas (check obligatorio para hacer merge)
  release.yml       tag v#.#.# → release en GitHub con el repo en zip
  deploy.yml        release publicado → descarga el zip en la EC2 y reinicia
  health-check.yml  después de cada deploy (o manual) → /health, /version, /tasks
  provision.yml     terraform apply (manual)
  destroy.yml       terraform destroy (manual)
```

## Infraestructura (Terraform)

- **EC2** (Amazon Linux 2023, `t3.micro`) con Security Group (22 y 8000) y Key Pair.
  `user_data` clona el repo, crea un venv, instala dependencias y registra el servicio
  `systemd` `todo-api` (uvicorn en el puerto 8000). Usa `LabInstanceProfile` para tener
  permisos de Secrets Manager y CloudWatch.
- **RDS MySQL 8.0** (`db.t3.micro`), privado, accesible solo desde el SG de la EC2.
- **Secrets Manager**: `todo-api/db-credentials` con host, puerto, BD, usuario y password
  (generado con `random_password`). La app lo lee **en tiempo de ejecución** con boto3.
- **SNS + 3 alarmas + dashboard** de CloudWatch.
- **Estado remoto** en S3 (`backend "s3"`, el bucket se pasa con `-backend-config`).
  El `tfstate` nunca se sube al repo (`.gitignore`).

## CI/CD

1. **CI**: al abrir un PR hacia `main` corre `pytest`. La rama `main` está protegida:
   requiere PR y que el check `tests` pase.
2. **Release**: `git tag v1.0.0 && git push origin v1.0.0` → corre las pruebas, empaqueta el
   repo con `git archive` y crea el release con el zip adjunto.
3. **Deploy**: al publicarse el release, el workflow busca la EC2 por su tag `Name=todo-api`,
   se conecta por SSH, descarga el zip del release, instala dependencias, cambia el symlink
   `/opt/todo-api/current`, actualiza `APP_VERSION` y reinicia el servicio. Luego valida con
   `GET /version` que la versión corriendo sea la del tag.

## Observabilidad

| # | Métrica | Tipo | Alarma | Por qué |
|---|---|---|---|---|
| 1 | `AWS/EC2 CPUUtilization` | Nativa | Promedio > 80 % en 3 periodos de 5 min (15 min sostenidos) | Un pico breve de CPU es normal (p.ej. al instalar dependencias en un deploy); 15 min sostenidos indican saturación real. **Acción**: revisar tráfico/procesos y, si es carga legítima, subir el tipo de instancia. |
| 2 | `TodoApi DatabaseErrors` | `put_metric_data` | Suma ≥ 1 en 2 de los últimos 3 minutos | Cada error es una petición fallida del usuario (503). Se pide 2 de 3 minutos para no alertar por un solo fallo transitorio de red, pero detectar en ~2 min una caída real. **Acción**: revisar si RDS está detenida/reiniciando, conexiones o credenciales del secret, y los logs (`journalctl -u todo-api`). |
| 3 | `TodoApi TasksCreated` | `put_metric_data` | Suma ≥ 20 en 5 min | Mide el uso real del to-do-list (cuántas tareas se crean). Un usuario normal crea pocas tareas; 20+ en 5 min sugiere un bot/spam o un cliente en un ciclo, que puede llenar la BD. **Acción**: revisar el origen de las peticiones y considerar rate limiting / autenticación. |

- Los errores de RDS se cuentan en `GET /tasks` (lectura), `POST /tasks` (escritura) y `GET /health`.
- Las alarmas notifican (ALARM y OK) al tópico SNS `todo-api-alerts`, suscrito por correo.
- Dashboard `todo-api` con las 3 métricas y las líneas de umbral.

**Validación de DatabaseErrors**: detener la RDS
(`aws rds stop-db-instance --db-instance-identifier todo-api-db`), generar tráfico contra
`/health` y `/tasks`, ver subir la métrica y llegar el correo de la alarma; luego
`aws rds start-db-instance ...` y la alarma regresa a OK.

## Desarrollo local

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
pytest -v
DATABASE_URL=sqlite:///local.db uvicorn main:app --app-dir src --reload
```

