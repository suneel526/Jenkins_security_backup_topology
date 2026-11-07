resource "aws_ecr_repository" "payment_service" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, { Name = var.ecr_repository_name })
}

resource "aws_ecr_lifecycle_policy" "payment_service" {
  repository = aws_ecr_repository.payment_service.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images older than 14 days; retain tagged immutable releases"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 14
      }
      action = { type = "expire" }
    }]
  })
}
