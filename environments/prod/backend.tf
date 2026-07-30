terraform {
  # Partial backend configuration — see environments/dev/backend.tf for the
  # rationale. Concrete values come from bootstrap outputs at init time:
  #
  #   terraform init -backend-config=backend.hcl
  #
  # prod uses a distinct state key but the same bucket and lock table as dev.
  backend "s3" {
    key     = "env/prod/terraform.tfstate"
    encrypt = true
  }
}
