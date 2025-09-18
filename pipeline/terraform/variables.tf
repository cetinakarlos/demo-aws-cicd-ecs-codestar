variable "region" {
  description = "AWS region"
  type        = string
}
variable "app_name" {
  description = "Nombre del stack/app"
  type        = string
}
variable "artifact_bucket_name" {
  description = "Bucket S3 artifacts"
  type        = string
}
variable "cluster_name" {
  description = "Nombre ECS cluster"
  type        = string
}
variable "service_name" {
  description = "Nombre ECS service"
  type        = string
}
variable "prod_listener_arn" {
  description = "ARN listener prod ALB"
  type        = string
}
variable "test_listener_arn" {
  description = "ARN listener test ALB"
  type        = string
}
variable "tg_blue_name" {
  description = "Target group azul"
  type        = string
}
variable "tg_green_name" {
  description = "Target group verde"
  type        = string
}
variable "vpc_id" {
  description = "VPC donde viven los Target Groups del ALB"
  type        = string
}

variable "s3_source_bucket" {
  type    = string
  default = null
}
variable "s3_source_object_key" {
  type    = string
  default = null
}

variable "public_subnet_ids" {
  description = "Subnets para el ALB (2+ AZs)"
  type        = list(string)
  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "Provide at least two subnet IDs in different AZs."
  }
}

variable "use_github" {
  type    = bool
  default = true
}
variable "github_repo" {
  type = string
} # "usuario/repo"


variable "use_codecommit" {
  description = "Si true, crea y usa CodeCommit como Source"
  type        = bool
  default     = false
}

variable "create_cluster" {
  type    = bool
  default = true
} # crea el cluster si true

variable "task_family" { type = string } # p.ej. "demo-cicd-ecs"
variable "exec_role_name" {
  type    = string
  default = "ecsTaskExecutionRole"
}
variable "task_role_name" {
  type    = string
  default = "ecsAppRole"
}
variable "codepipeline_role_name" {
  type    = string
  default = "codestar-codepipeline-role"
}

variable "repo_name" {
  type = string
}
variable "create_task_role_if_missing" {
  type    = bool
  default = true
}






variable "ecr_repo_name" {
  type    = string
  default = ""
} # si vacío, usa app_name
variable "create_ecr_repo" {
  type    = bool
  default = true
}