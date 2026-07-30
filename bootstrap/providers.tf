provider "aws" {
  region = var.aws_region

  # Every taggable resource created here inherits the mandatory tag schema.
  default_tags {
    tags = module.tags.tags
  }
}
