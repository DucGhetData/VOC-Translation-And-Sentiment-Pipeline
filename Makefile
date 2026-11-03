# ============================================================
# VOC Pipeline — Makefile
# Run: make <target>
# ============================================================

.PHONY: help install install-dev dependency-check lint format type-check test test-unit \
        airflow-build airflow-up airflow-down airflow-logs airflow-restart \
        smoke-test tf-version tf-fmt tf-init tf-validate tf-plan tf-apply tf-destroy \
        clean

PYTHON := venv\Scripts\python.exe
PIP    := venv\Scripts\pip.exe
TF     := docker compose -f docker-compose.terraform.yml run --rm terraform

# ── Default: show help ────────────────────────────────────────────────────────
help:
	@echo.
	@echo  VOC Pipeline — Available Make Targets
	@echo  ======================================
	@echo  install          Install runtime Python dependencies into venv
	@echo  install-dev      Install runtime + test/dev dependencies
	@echo  dependency-check Verify the installed dependency graph
	@echo  lint             Run ruff linter
	@echo  format           Run black formatter
	@echo  type-check       Run mypy type checker
	@echo  test             Run all tests with coverage
	@echo  test-unit        Run unit tests only
	@echo  airflow-build    Build the shared Airflow image
	@echo  airflow-up       Start Airflow (Docker Compose)
	@echo  airflow-down     Stop Airflow
	@echo  airflow-logs     Tail Airflow logs
	@echo  smoke-test       Run Phase 1 S3 connectivity smoke test
	@echo  tf-version       Show the Dockerized Terraform version
	@echo  tf-fmt           Format Terraform files
	@echo  tf-init          Terraform init (dev, Docker)
	@echo  tf-validate      Validate Terraform configuration
	@echo  tf-plan          Terraform plan (dev)
	@echo  tf-apply         Terraform apply (dev)
	@echo  tf-destroy       Terraform destroy (dev)
	@echo  clean            Remove __pycache__ and .pyc files
	@echo.

# ── Python / venv ─────────────────────────────────────────────────────────────
install:
	$(PIP) install --upgrade pip
	$(PIP) install -r requirements.txt
	$(PIP) check

install-dev:
	$(PIP) install --upgrade pip
	$(PIP) install -r requirements-dev.txt
	$(PIP) check

dependency-check:
	$(PIP) check

# ── Code Quality ─────────────────────────────────────────────────────────────
lint:
	$(PYTHON) -m ruff check src/ dags/ tests/

format:
	$(PYTHON) -m black src/ dags/ tests/

type-check:
	$(PYTHON) -m mypy src/

# ── Testing ───────────────────────────────────────────────────────────────────
test:
	$(PYTHON) -m pytest tests/ -v

test-unit:
	$(PYTHON) -m pytest tests/unit/ -v

# ── Airflow ───────────────────────────────────────────────────────────────────
airflow-build:
	docker compose build airflow-init

airflow-up:
	docker compose build airflow-init
	docker compose up -d
	@echo Airflow UI: http://localhost:8080  ^(user: airflow / pass: airflow^)

airflow-down:
	docker compose down

airflow-restart:
	docker compose restart airflow-scheduler airflow-webserver

airflow-logs:
	docker compose logs -f airflow-scheduler airflow-webserver

# ── Smoke Test ────────────────────────────────────────────────────────────────
smoke-test:
	$(PYTHON) scripts/smoke_test_s3.py

# ── Terraform ────────────────────────────────────────────────────────────────
tf-version:
	$(TF) version

tf-fmt:
	$(TF) fmt -recursive /workspace/terraform

tf-init:
	$(TF) init

tf-validate:
	$(TF) validate

tf-plan:
	$(TF) plan

tf-apply:
	$(TF) apply

tf-destroy:
	$(TF) destroy

# ── Cleanup ───────────────────────────────────────────────────────────────────
clean:
	for /r . %%d in (__pycache__) do @if exist "%%d" rd /s /q "%%d"
	del /s /q *.pyc 2>nul
	@echo Cleaned.
