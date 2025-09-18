terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ===== S3 artifacts =====
resource "aws_s3_bucket" "artifacts" {
  bucket = var.artifact_bucket_name
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}


# Política de ciclo de vida (limitar imágenes antiguas)
resource "aws_ecr_lifecycle_policy" "repo_policy" {
  count      = local.ecr_repo_name != null ? 1 : 0
  repository = local.ecr_repo_name
  policy = jsonencode({
    rules = [{
      rulePriority = 1,
      description  = "Keep last 30 images",
      selection = {
        tagStatus   = "any",
        countType   = "imageCountMoreThan",
        countNumber = 30
      },
      action = { type = "expire" }
    }]
  })
}

# ===== CodeStar AWS =====
resource "aws_codecommit_repository" "repo" {
  count           = var.use_codecommit ? 1 : 0
  repository_name = var.app_name
  description     = "KS DevOps Tools demo"
}

# Conexión a GitHub para CodePipeline (requiere handshake en consola)
resource "aws_codestarconnections_connection" "github" {
  count         = var.use_github ? 1 : 0
  name          = "${var.app_name}-github-conn"
  provider_type = "GitHub"
}

# ===== IAM ROLES =====
locals {
  codecommit_stmt = var.use_codecommit ? [
    {
      Effect = "Allow",
      Action = [
        "codecommit:GetBranch",
        "codecommit:GetCommit",
        "codecommit:UploadArchive",
        "codecommit:GetUploadArchiveStatus",
        "codecommit:CancelUploadArchive"
      ],
      Resource = "*" # o limita a ARN si lo estás creando
    }
  ] : []
}

resource "aws_iam_role_policy" "codepipeline_inline" {
  name = "${var.app_name}-codepipeline-inline"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = concat([
      {
        Effect = "Allow",
        Action = ["s3:*"],
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      },
      { Effect = "Allow", Action = ["codebuild:BatchGetBuilds", "codebuild:StartBuild", "codebuild:BatchGetProjects"], Resource = "*" },
      { Effect = "Allow", Action = ["codedeploy:*"], Resource = "*" },
      { Effect = "Allow", Action = ["iam:PassRole"], Resource = "*" }
    ], local.codecommit_stmt)
  })
}

data "aws_iam_policy_document" "assume_codebuild" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${var.app_name}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.assume_codebuild.json
}

resource "aws_iam_role_policy" "codebuild_inline" {
  name = "${var.app_name}-codebuild-inline"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = concat([
      { "Effect" : "Allow", "Action" : ["ecr:GetAuthorizationToken"], "Resource" : "*" },
      { "Effect" : "Allow", "Action" : ["logs:*"], "Resource" : "*" },
      { "Effect" : "Allow", "Action" : ["s3:*"], "Resource" : [
        aws_s3_bucket.artifacts.arn,
        "${aws_s3_bucket.artifacts.arn}/*"
        ]
      }
    ], local.ecr_write_stmt)
  })
}

data "aws_iam_policy_document" "assume_codedeploy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codedeploy.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codedeploy" {
  name               = "${var.app_name}-codedeploy-role"
  assume_role_policy = data.aws_iam_policy_document.assume_codedeploy.json
}

data "aws_iam_policy" "codedeploy_ecs_managed" {
  name = "AWSCodeDeployRoleForECS"
}

resource "aws_iam_role_policy_attachment" "codedeploy_managed" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = data.aws_iam_policy.codedeploy_ecs_managed.arn
}


data "aws_iam_policy_document" "assume_codepipeline" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codepipeline" {
  name               = "${var.app_name}-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.assume_codepipeline.json
}

# Rol IAM para CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name = "codestar-codebuild-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "codebuild.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# Política inline mínima para ECR + S3 + Logs
resource "aws_iam_role_policy" "codebuild_ecr_policy" {
  name = "codebuild-ecr-policy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "ECRAuth",
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken"
        ],
        Resource = "*"
      },
      {
        Sid    = "ECRDescribeCreate",
        Effect = "Allow",
        Action = [
          "ecr:DescribeRepositories",
          "ecr:CreateRepository",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:GetRepositoryPolicy",
          "ecr:SetRepositoryPolicy",
          "ecr:TagResource",
          "ecr:UntagResource"
        ],
        Resource = "arn:aws:ecr:us-east-1:${data.aws_caller_identity.current.account_id}:repository/demo-aws-cicd-ecs-codestar"
      },
      {
        Sid    = "ECRPushPull",
        Effect = "Allow",
        Action = [
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer"
        ],
        Resource = "arn:aws:ecr:us-east-1:${data.aws_caller_identity.current.account_id}:repository/demo-aws-cicd-ecs-codestar"
      },
      {
        Sid    = "LogsAndS3",
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "s3:GetObject",
          "s3:PutObject",
          "s3:GetObjectVersion",
          "s3:GetBucketAcl",
          "s3:GetBucketLocation"
        ],
        Resource = "*"
      }
    ]
  })
}

############################
# Descubrir cuenta / región
############################
data "aws_caller_identity" "me" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.me.account_id
  region     = coalesce(var.region, data.aws_region.current.name)

  ecs_cluster_arn = "arn:aws:ecs:${local.region}:${local.account_id}:cluster/${var.cluster_name}"
  ecs_service_arn = "arn:aws:ecs:${local.region}:${local.account_id}:service/${var.cluster_name}/${var.service_name}"
  taskdef_arn     = "arn:aws:ecs:${local.region}:${local.account_id}:task-definition/${var.task_family}:*"
}

############################
# Roles (exec obligatorio, task opcional)
############################
# Exec role por nombre (debe existir; si no, créalo como recurso aparte)
data "aws_iam_role" "exec" { name = var.exec_role_name }

# Si el usuario da nombre de task role, lo buscamos; si no, lo creamos vacío (trust a ECS)
data "aws_iam_role" "task" {
  count = var.task_role_name != "" ? 1 : 0
  name  = var.task_role_name
}

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task" {
  count              = var.task_role_name == "" && var.create_task_role_if_missing ? 1 : 0
  name               = "${var.service_name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# ARN unificado (usa el que haya)
locals {
  task_role_arn = coalesce(
    try(data.aws_iam_role.task[0].arn, null), # si existe por nombre
    try(aws_iam_role.task[0].arn, null),      # si lo creamos nosotros
    null
  )
}

############################
# Policy mínima para CodePipeline → ECS
############################
data "aws_iam_role" "codepipeline" { name = var.codepipeline_role_name }

# Recursos que CodePipeline puede pasar (solo los que existan)
locals {
  passrole_resources = compact([data.aws_iam_role.exec.arn, local.task_role_arn])
}

resource "aws_iam_policy" "codepipeline_ecs_deploy" {
  name        = "codepipeline-ecs-deploy-min"
  description = "Permisos para registrar TaskDef y actualizar Service ECS"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "ECSRegisterAndUpdate",
        Effect = "Allow",
        Action = [
          "ecs:RegisterTaskDefinition",
          "ecs:DescribeTaskDefinition",
          "ecs:DescribeClusters",
          "ecs:DescribeServices",
          "ecs:UpdateService",
          "ecs:ListTasks",
          "ecs:DescribeTasks"
        ],
        Resource = [
          local.taskdef_arn,
          local.ecs_cluster_arn,
          local.ecs_service_arn
        ]
      },
      {
        Sid      = "PassTaskRoles",
        Effect   = "Allow",
        Action   = "iam:PassRole",
        Resource = local.passrole_resources,
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      },
      {
        Sid    = "ELBDescribeReadOnly",
        Effect = "Allow",
        Action = [
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeRules"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_codepipeline_ecs" {
  role       = data.aws_iam_role.codepipeline.name
  policy_arn = aws_iam_policy.codepipeline_ecs_deploy.arn
}

# Útil para interpolar account_id
data "aws_caller_identity" "current" {}

# ===== CodeBuild =====
resource "aws_codebuild_project" "build" {
  name         = "${var.app_name}-build"
  service_role = aws_iam_role.codebuild.arn

  artifacts { type = "CODEPIPELINE" }

    environment {
      compute_type                = "BUILD_GENERAL1_SMALL"
      image                       = "aws/codebuild/standard:7.0"
      type                        = "LINUX_CONTAINER"
      privileged_mode             = true
      image_pull_credentials_type = "CODEBUILD"
      # env vars opcionales...
    }

  source { type = "CODEPIPELINE" }

  cache {
    type  = "LOCAL"
    modes = ["LOCAL_SOURCE_CACHE", "LOCAL_DOCKER_LAYER_CACHE"]
  }
}

# ===== IAM Policy to allow CodeBuild to pull from ECR
data "aws_iam_policy_document" "assume_ecs_tasks" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.app_name}-ecs-task-exec"
  assume_role_policy = data.aws_iam_policy_document.assume_ecs_tasks.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_attach" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ===== CodeDeploy (ECS CLUSTER AND SERVICE) =====
resource "aws_ecs_cluster" "this" {
  count = var.create_cluster ? 1 : 0
  name  = var.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Project = var.app_name
  }
}

resource "aws_codedeploy_app" "ecs" {
  name             = "${var.app_name}-app"
  compute_platform = "ECS"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.app_name}-td"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  # SOLO una vez:
  execution_role_arn = data.aws_iam_role.exec.arn
  # opcional: si no existe, local será null y el provider lo ignora
  task_role_arn = local.task_role_arn

  container_definitions = jsonencode([
    {
      name         = "app",
      image        = "public.ecr.aws/docker/library/node:20-alpine",
      essential    = true,
      portMappings = [{ containerPort = 3000 }],
      command = [
        "node", "-e",
        "require('http').createServer((q,r)=>{r.writeHead(200,{'Content-Type':'text/plain'});r.end('ok')}).listen(3000,'0.0.0.0')"
      ],
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = "/ecs/${var.app_name}",
          awslogs-region        = var.region,
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_security_group" "svc" {
  name        = "${var.app_name}-svc-sg"
  description = "Allow traffic from ALB to ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id] # el SG del ALB que ya definiste
    description     = "Desde ALB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_codedeploy_deployment_group" "ecs" {
  app_name               = aws_codedeploy_app.ecs.name
  deployment_group_name  = "${var.app_name}-dg"
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"

  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  blue_green_deployment_config {
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 0
    }
    deployment_ready_option {
      action_on_timeout    = "CONTINUE_DEPLOYMENT"
      wait_time_in_minutes = 0
    }
  }

  ecs_service {
    # ¡OJO! ECS quiere NOMBRES aquí
    cluster_name = var.create_cluster ? aws_ecs_cluster.this[0].name : var.cluster_name
    service_name = var.service_name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route { listener_arns = [aws_lb_listener.prod.arn] }
      test_traffic_route { listener_arns = [aws_lb_listener.test.arn] }
      target_group { name = aws_lb_target_group.blue.name }
      target_group { name = aws_lb_target_group.green.name }
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  depends_on = [aws_ecs_service.app]
}

resource "aws_ecs_service" "app" {
  name            = var.service_name
  cluster         = var.create_cluster ? aws_ecs_cluster.this[0].arn : var.cluster_name
  launch_type     = "FARGATE"
  desired_count   = 1
  task_definition = aws_ecs_task_definition.app.arn

  deployment_controller { type = "CODE_DEPLOY" }

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.svc.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = "app"
    container_port   = 3000
  }

  # 👇 evita que TF intente cambiar lo que maneja CodeDeploy
  lifecycle {
    ignore_changes = [
      task_definition, # las nuevas revisiones las aplica CodeDeploy
      desired_count    # opcional: si escalas con CD/auto-scaling
      # capacity_provider_strategy, # opcional
      # load_balancer              # si CodeDeploy hace swap
    ]
  }

  depends_on = [aws_lb_listener.prod, aws_lb_target_group.blue]
}

# ===== CodePipeline =====
resource "aws_codepipeline" "pipeline" {
  name     = var.app_name
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = var.use_github ? "CodeStarSourceConnection" : (var.use_codecommit ? "CodeCommit" : "S3")
      version          = "1"
      output_artifacts = ["SourceOut"]

      configuration = var.use_github ? {
        ConnectionArn    = aws_codestarconnections_connection.github[0].arn
        FullRepositoryId = var.github_repo
        BranchName       = "main"
        DetectChanges    = "true"
        } : (var.use_codecommit ? {
          RepositoryName       = var.app_name # 👈 sin referenciar recurso
          BranchName           = "main"
          PollForSourceChanges = "true"
          } : {
          S3Bucket             = var.s3_source_bucket
          S3ObjectKey          = var.s3_source_object_key
          PollForSourceChanges = "false"
      })
    }
  }

  stage {
    name = "Build"
    action {
      name             = "BuildImage"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOut"]
      output_artifacts = ["BuildOut"]
      configuration = {
        ProjectName = aws_codebuild_project.build.name
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "BlueGreen"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      version         = "1"
      input_artifacts = ["BuildOut"]

      configuration = {
        ApplicationName                = aws_codedeploy_app.ecs.name
        DeploymentGroupName            = aws_codedeploy_deployment_group.ecs.deployment_group_name
        TaskDefinitionTemplateArtifact = "BuildOut"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "BuildOut"
        AppSpecTemplatePath            = "appspec.json"
      }
    }
  }
}

# ===== ALB =========
# --- Security Group para el ALB ---
resource "aws_security_group" "alb_sg" {
  name        = "${var.app_name}-alb-sg"
  description = "ALB SG"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP prod"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP test"
    from_port   = 3000
    to_port     = 3001
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

# --- ALB ---
# Resolver info de las subnets pasadas
data "aws_subnet" "selected" {
  for_each = toset(var.public_subnet_ids)
  id       = each.value
}

locals {
  selected_azs  = toset([for s in data.aws_subnet.selected : s.availability_zone])
  selected_vpcs = toset([for s in data.aws_subnet.selected : s.vpc_id])
}

resource "aws_lb" "app" {
  name               = "codestar-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnet_ids

  lifecycle {
    precondition {
      condition     = length(local.selected_azs) >= 2
      error_message = "Debes pasar subnets en AZs distintas (min 2)."
    }
    precondition {
      condition     = length(local.selected_vpcs) == 1 && one(local.selected_vpcs) == var.vpc_id
      error_message = "Todas las subnets deben pertenecer a la VPC indicada."
    }
  }
}

# --- Target Groups (blue/green) ---
resource "aws_lb_target_group" "blue" {
  name        = "tg-blue"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
  }
}

resource "aws_lb_target_group" "green" {
  name        = "tg-green"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
  }
}

# --- Listeners: prod (80) → blue, test (9001) → green ---
resource "aws_lb_listener" "prod" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}

resource "aws_lb_listener" "test" {
  load_balancer_arn = aws_lb.app.arn
  port              = 3000
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green.arn
  }
}

locals {
  effective_ecr_repo_name = var.ecr_repo_name != "" ? var.ecr_repo_name : var.app_name
}

resource "aws_ecr_repository" "repo" {
  count = var.create_ecr_repo ? 1 : 0
  name  = local.effective_ecr_repo_name
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
  force_delete = true
}

data "aws_ecr_repository" "existing" {
  count = var.create_ecr_repo ? 0 : 1
  name  = local.effective_ecr_repo_name
}

# Normaliza salidas del ECR, funcione lo crees o lo leas
locals {
  ecr_repo_name = coalesce(
    try(aws_ecr_repository.repo[0].name, null),
    try(data.aws_ecr_repository.existing[0].name, null)
  )
  ecr_repo_arn = coalesce(
    try(aws_ecr_repository.repo[0].arn, null),
    try(data.aws_ecr_repository.existing[0].arn, null)
  )
  ecr_repo_url = coalesce(
    try(aws_ecr_repository.repo[0].repository_url, null),
    try(data.aws_ecr_repository.existing[0].repository_url, null)
  )
}

locals {
  ecr_write_stmt = local.ecr_repo_arn != null ? [
    {
      Effect = "Allow",
      Action = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:CompleteLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:BatchGetImage",
        "ecr:DescribeRepositories",
        "ecr:GetDownloadUrlForLayer"
      ],
      Resource = local.ecr_repo_arn
    }
  ] : []
}
