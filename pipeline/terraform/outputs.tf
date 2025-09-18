output "alb_dns_name" { value = aws_lb.app.dns_name }
output "listener_prod" { value = aws_lb_listener.prod.arn }
output "listener_test" { value = aws_lb_listener.test.arn }
output "tg_blue_arn" { value = aws_lb_target_group.blue.arn }
output "tg_green_arn" { value = aws_lb_target_group.green.arn }
# Salidas para clonar
output "codecommit_clone_url_http" {
  value       = try(aws_codecommit_repository.repo[0].clone_url_http, null)
  description = "URL HTTP del repo CodeCommit (si se creó)"
}

output "codecommit_clone_url_ssh" {
  value       = try(aws_codecommit_repository.repo[0].clone_url_ssh, null)
  description = "URL SSH del repo CodeCommit (si se creó)"
}

