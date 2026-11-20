variable "aws_region" {
  description = "Región de AWS (Learner Lab usa us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "repo_url" {
  description = "URL HTTPS del repositorio público que se clona en user_data"
  type        = string
}

variable "public_key" {
  description = "Llave pública SSH (contenido de ~/.ssh/todo-api.pub)"
  type        = string
}

variable "alert_email" {
  description = "Correo que recibe las notificaciones de las alarmas (SNS)"
  type        = string
}

variable "instance_name" {
  description = "Tag Name de la EC2 (los workflows la buscan por este nombre)"
  type        = string
  default     = "todo-api"
}

variable "instance_type" {
  description = "Tipo de instancia EC2"
  type        = string
  default     = "t3.micro"
}

variable "instance_profile_name" {
  description = "Instance profile con permisos para Secrets Manager y CloudWatch (en Learner Lab: LabInstanceProfile)"
  type        = string
  default     = "LabInstanceProfile"
}

variable "app_port" {
  description = "Puerto donde escucha la API"
  type        = number
  default     = 8000
}

variable "app_version" {
  description = "Versión inicial que reporta /version antes del primer deploy"
  type        = string
  default     = "main"
}

variable "db_identifier" {
  description = "Identificador de la instancia RDS"
  type        = string
  default     = "todo-api-db"
}

variable "db_instance_class" {
  description = "Clase de instancia RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Nombre de la base de datos"
  type        = string
  default     = "todos"
}

variable "db_username" {
  description = "Usuario administrador de RDS"
  type        = string
  default     = "todoadmin"
}

variable "db_secret_name" {
  description = "Nombre del secret en Secrets Manager con las credenciales de RDS"
  type        = string
  default     = "todo-api/db-credentials"
}
