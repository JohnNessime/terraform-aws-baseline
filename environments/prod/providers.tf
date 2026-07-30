provider "aws" {
  region = var.aws_region

  # Mandatory tag schema, applied to every taggable resource in the environment.
  default_tags {
    tags = module.tags.tags
  }
}
