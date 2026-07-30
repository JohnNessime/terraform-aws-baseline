terraform {
  # Partial backend configuration. The concrete values — bucket name (which
  # embeds the account ID), lock table, KMS key — are supplied at init time and
  # kept out of version control:
  #
  #   terraform init -backend-config=backend.hcl
  #
  # See backend.hcl.example for the required keys; they are exactly the outputs
  # of the bootstrap module. This is why nothing here reveals the account.
  backend "s3" {
    key     = "env/dev/terraform.tfstate"
    encrypt = true
  }
}
