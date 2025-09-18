region = "us-east-1"

# prod_listener_arn = "arn:aws:elasticloadbalancing:...:listener/app/..."
# test_listener_arn = "arn:aws:elasticloadbalancing:...:listener/app/..."

tg_blue_name      = "tg-blue"
tg_green_name     = "tg-green"
vpc_id            = "vpc-1111111112222222" # <-- input your vpc id here
public_subnet_ids = ["subnet-1111111112222222", "subnet-1111111112222222"] # en AZs distintas

app_name       = "codestar"
use_github     = true
use_codecommit = false
github_repo    = "usergithub/repo-codestar-ecs" # <-- input your github repo here

cluster_name                = "codestar-ecs-cluster"
service_name                = "demo-ecs-service"
artifact_bucket_name        = "ks-devops-artifacts-demo"
task_family                 = "demo-cicd-ecs"
exec_role_name              = "ecsTaskExecutionRole"
repo_name                   = "demo-ecs-repo"
task_role_name              = ""
create_task_role_if_missing = true
codepipeline_role_name      = "codestar-codepipeline-role"
create_ecr_repo             = false
ecr_repo_name               = "demo-aws-cicd-ecs-codestar"
