COMPOSE := docker compose

.PHONY: help up down build logs ps migrate revision test test-backend test-frontend lint fmt clean shell-backend shell-db deploy-backend destroy-backend logs-backend migrate-backend cert domain deploy-frontend destroy-frontend github-role auth-uris report-now llm-hello parse ai-logs ai-budget push-image infra-init infra-fmt infra-validate infra-plan infra-output tf-vars tf-imports cfn-retain cfn-delete

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

up: ## Start the whole stack (detached)
	$(COMPOSE) up -d --build

down: ## Stop the stack
	$(COMPOSE) down

clean: ## Stop the stack and wipe the database volume
	$(COMPOSE) down -v

build: ## Rebuild images
	$(COMPOSE) build

logs: ## Tail all logs
	$(COMPOSE) logs -f

ps: ## Show service status
	$(COMPOSE) ps

migrate: ## Apply migrations
	$(COMPOSE) exec backend alembic upgrade head

revision: ## Autogenerate a migration: make revision m="add x"
	$(COMPOSE) exec backend alembic revision --autogenerate -m "$(m)"

test: test-backend test-frontend ## Run all tests

test-backend: ## Run backend tests
	$(COMPOSE) exec backend pytest

test-frontend: ## Run frontend tests
	$(COMPOSE) exec frontend pnpm test

lint: ## Lint both sides
	$(COMPOSE) exec backend ruff check .
	$(COMPOSE) exec frontend pnpm lint

fmt: ## Format both sides
	$(COMPOSE) exec backend ruff format .
	$(COMPOSE) exec frontend pnpm format

shell-backend: ## Shell into the backend container
	$(COMPOSE) exec backend bash

shell-db: ## psql into the database
	$(COMPOSE) exec db psql -U $${POSTGRES_USER:-spry} -d $${POSTGRES_DB:-spry}

deploy-backend: ## Build + push the image (tagged with the commit SHA), roll the ECS service; IMAGE_TAG=<sha> redeploys an old image
	./scripts/deploy-backend.sh

rollback-backend: ## Redeploy an earlier image: make rollback-backend IMAGE_TAG=<sha>
	@test -n "$(IMAGE_TAG)" || { echo "usage: make rollback-backend IMAGE_TAG=<sha>"; exit 2; }
	IMAGE_TAG=$(IMAGE_TAG) ./scripts/deploy-backend.sh

destroy-backend: ## Delete the backend stack, database included
	./scripts/destroy-backend.sh

logs-backend: ## Tail the deployed backend's CloudWatch logs
	aws logs tail /ecs/$${PROJECT_NAME:-spry}-backend --follow --since 10m

cert-backend: ## Request + DNS-validate the API's certificate: make cert-backend API_DOMAIN=api.example.com
	./scripts/domain-backend.sh

cert: ## Request + DNS-validate a us-east-1 certificate for the frontend: make cert DOMAIN=app.example.com
	./scripts/domain-frontend.sh cert

domain: ## Assign a custom domain to the frontend: make domain DOMAIN=app.example.com
	./scripts/domain-frontend.sh domain

deploy-frontend: ## Build the static export against BACKEND_URL and ship it to S3 + CloudFront
	./scripts/deploy-frontend.sh

destroy-frontend: ## Delete the frontend stack (bucket + distribution)
	./scripts/destroy-frontend.sh

github-role: ## Create the IAM role GitHub Actions assumes to deploy (OIDC, no keys)
	./scripts/github-role.sh

auth-uris:
	./scripts/auth.sh uris

report-now: ## Lab 5: build a report on demand: make report-now WEEK=2026-W40
	./scripts/reports.sh now $(WEEK)

llm-hello: ## Lab 6: first call to Claude on Bedrock, from your laptop (needs AWS credentials)
	cd backend && uv run python -m app.ai.hello

parse: ## Lab 6: run the parser from your laptop: make parse TEXT="Mon 10:00 sync, 30 min. 1) pricing"
	cd backend && uv run python -m app.ai.cli "$(TEXT)"

ai-logs: ## Lab 6: the parser's log lines from the last hour
	./scripts/ai.sh logs

# ---- Lab 7: the infrastructure is Terraform (infra/*.tf), applied by HCP Terraform ----
# There is no `terraform apply` here on purpose: changes reach AWS by a pull request and a merge.

push-image: ## Build the Lambda image, push it to ECR, print its URI (set it as image_uri in the workspace)
	./scripts/push-image.sh

infra-init: ## Terraform: download providers, connect to the HCP Terraform workspace
	terraform -chdir=infra init

infra-fmt: ## Terraform: format the files
	terraform -chdir=infra fmt

infra-validate: ## Terraform: check syntax, types and references (no AWS calls)
	terraform -chdir=infra validate

infra-plan: ## Terraform: show what would change (read-only)
	terraform -chdir=infra plan

infra-output: ## Terraform: print all outputs
	terraform -chdir=infra output

tf-vars: ## Lab 7 Step 3: write infra/terraform.tfvars from the old stacks' parameters
	./scripts/tf-vars.sh

tf-imports: ## Lab 7 Step 3b: write infra/imports.tf from what exists in AWS
	./scripts/tf-imports.sh

cfn-retain: ## Lab 7 Step 3a: redeploy the old stacks with DeletionPolicy: Retain
	./scripts/cfn-release.sh retain

cfn-delete: ## Lab 7 Step 3a: delete the old stacks; their resources stay (checks Retain first)
	./scripts/cfn-release.sh delete

ai-budget: ## Create the $5 monthly AWS Budgets alarm
	./scripts/ai.sh budget
