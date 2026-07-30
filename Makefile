# Static Terraform quality gates — the same checks CI runs, runnable locally.
# Every target here is offline: no AWS credentials, no `terraform plan`, no
# cloud access of any kind.

# Order matters: modules first (leaf → composition), then the roots.
TF_DIRS := modules/tags modules/vpc modules/iam bootstrap environments/dev environments/prod

.PHONY: all fmt fmt-fix validate lint scan clean help

help: ## Show this help
	@echo "Targets:"
	@echo "  fmt       Check formatting (terraform fmt -check)"
	@echo "  fmt-fix   Rewrite files to canonical format"
	@echo "  validate  terraform init -backend=false && validate, per directory"
	@echo "  lint      tflint with the AWS ruleset, per directory"
	@echo "  scan      checkov static security scan"
	@echo "  all       fmt + validate + lint + scan"

fmt: ## Verify canonical formatting
	terraform fmt -check -recursive -diff

fmt-fix: ## Rewrite files to canonical formatting
	terraform fmt -recursive

validate: ## Validate every module and environment
	@set -e; for d in $(TF_DIRS); do \
		echo "== validate $$d =="; \
		terraform -chdir=$$d init -backend=false -input=false >/dev/null; \
		terraform -chdir=$$d validate; \
	done

lint: ## Run tflint (AWS ruleset) across all directories
	@tflint --init --config="$(CURDIR)/.tflint.hcl" >/dev/null
	@set -e; for d in $(TF_DIRS); do \
		echo "== tflint $$d =="; \
		tflint --chdir=$$d --config="$(CURDIR)/.tflint.hcl"; \
	done

scan: ## Static security scan with checkov
	checkov -d . --config-file .checkov.yaml --compact --quiet

all: fmt validate lint scan ## Run every gate

clean: ## Remove local terraform working directories
	find . -type d -name ".terraform" -prune -exec rm -rf {} +
