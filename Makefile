.PHONY: help install test lint sla validate-network wifi forecast tf-fmt tf-validate monitoring-up

help:            ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'

install:         ## Install Python dependencies
	pip install -r requirements-dev.txt

lint:            ## Lint Python
	ruff check .

test: lint       ## Lint + run tests
	pytest

sla:             ## SLA gap report from baseline metrics
	-python scripts/sla_report.py data/baseline-metrics.json

validate-network: ## Validate VLAN plan and core configs
	python scripts/validate_network.py

wifi:            ## Wi-Fi survey report
	-python scripts/wifi_survey_report.py network/wireless/site-survey-results.csv

forecast:        ## Capacity forecast
	python scripts/capacity_forecast.py data/monthly-usage.csv

tf-fmt:          ## Format Terraform
	terraform fmt -recursive terraform/

tf-validate:     ## Validate both Terraform environments (no backend)
	cd terraform/environments/prod && terraform init -backend=false -input=false && terraform validate
	cd terraform/environments/dr && terraform init -backend=false -input=false && terraform validate

monitoring-up:   ## Start the on-prem monitoring stack
	docker compose -f monitoring/docker-compose.yml up -d
