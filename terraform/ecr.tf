resource "aws_ecr_repository" "app" {
  name                 = var.ecs_image_repo_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}