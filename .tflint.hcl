config {
  # Fail on warnings too — this is a portfolio repo; lint noise is a smell.
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# AWS ruleset: catches invalid instance types, deprecated arguments, missing
# required attributes, and naming-convention drift before an apply ever runs.
plugin "aws" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
