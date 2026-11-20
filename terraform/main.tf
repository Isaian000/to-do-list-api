terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Backend remoto en S3. El nombre del bucket se pasa en `terraform init`:
  #   terraform init -backend-config="bucket=<tu-bucket>"
  backend "s3" {
    key     = "todo-api/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project = "to-do-list-api"
    }
  }
}

# ---------------------------------------------------------------------------
# Red
# ---------------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_security_group" "app" {
  name        = "todo-api-app-sg"
  description = "to-do-list-api: SSH y puerto de la API"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH (deploy desde GitHub Actions)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "API"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db" {
  name        = "todo-api-db-sg"
  description = "to-do-list-api: MySQL solo desde la EC2"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "MySQL desde la app"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------------------------
# Base de datos (RDS) + credenciales en Secrets Manager
# ---------------------------------------------------------------------------
resource "random_password" "db" {
  length           = 20
  special          = true
  override_special = "!#%^*-_=+" # RDS no acepta / @ " ni espacios
}

resource "aws_db_instance" "todo" {
  identifier              = var.db_identifier
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = var.db_instance_class
  allocated_storage       = 20
  storage_type            = "gp2"
  db_name                 = var.db_name
  username                = var.db_username
  password                = random_password.db.result
  vpc_security_group_ids  = [aws_security_group.db.id]
  publicly_accessible     = false
  multi_az                = false
  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true
}

resource "aws_secretsmanager_secret" "db" {
  name                    = var.db_secret_name
  description             = "Credenciales de RDS para to-do-list-api"
  recovery_window_in_days = 0 # permite recrearlo de inmediato tras un destroy
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    engine   = "mysql"
    host     = aws_db_instance.todo.address
    port     = aws_db_instance.todo.port
    dbname   = var.db_name
    username = var.db_username
    password = random_password.db.result
  })
}

# ---------------------------------------------------------------------------
# EC2
# ---------------------------------------------------------------------------
resource "aws_key_pair" "deployer" {
  key_name   = "todo-api-key"
  public_key = var.public_key
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.deployer.key_name
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = var.instance_profile_name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    repo_url       = var.repo_url
    app_version    = var.app_version
    app_port       = var.app_port
    db_secret_name = aws_secretsmanager_secret.db.name
    aws_region     = var.aws_region
  })
  user_data_replace_on_change = true

  tags = {
    Name = var.instance_name
  }

  # La app lee el secret al arrancar: que ya exista con el host de RDS.
  depends_on = [aws_secretsmanager_secret_version.db]
}

# ---------------------------------------------------------------------------
# Observabilidad: SNS + alarmas + dashboard
# Las definiciones viven en ../alerting/*.json
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "todo-api-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  alarms = { for a in jsondecode(file("${path.module}/../alerting/alarms.json")) : a.name => a }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name          = each.key
  alarm_description   = each.value.description
  namespace           = each.value.namespace
  metric_name         = each.value.metric_name
  statistic           = each.value.statistic
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  datapoints_to_alarm = each.value.datapoints_to_alarm
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison_operator
  treat_missing_data  = each.value.treat_missing_data

  dimensions = {
    for d in each.value.dimensions : d.name => replace(d.value, "INSTANCE_ID", aws_instance.app.id)
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "todo" {
  dashboard_name = "todo-api"
  dashboard_body = replace(
    replace(file("${path.module}/../alerting/cloudwatch-dashboard.json"), "INSTANCE_ID", aws_instance.app.id),
    "REGION", var.aws_region
  )
}
