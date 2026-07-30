terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  # No backend block on purpose. Bootstrap runs with LOCAL state because the S3
  # backend it creates cannot yet exist to hold its own creation. After the
  # first apply, migrate this state into the bucket — see docs/bootstrap.md.
}
