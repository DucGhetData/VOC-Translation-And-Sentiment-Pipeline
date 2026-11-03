# ============================================================
# VOC Pipeline — Makefile
# Run: make <target>
# ============================================================

.PHONY: help install install-dev lint format type-check test test-unit \
        airflow-up airflow-down airflow-logs airflow-restart \
        smoke-test tf-init tf-plan tf-apply tf-destroy \
        clean

PYTHON := .venv\Scripts\python.exe
PIP    := .venv\Scripts\pip.exe

# ── Default: show help ────────────────────────────────────────────────────────
help:
	@echo.
	@echo  VOC Pipeline — Available Make Targets
	@echo  ======================================
	@echo  install          Install all Python dependencies into venv
	@echo  install-dev      Install dev/lint tools
	@echo  lint             Run ruff linter
	@echo  format           Run black formatter
	@echo  type-check       Run mypy type checker
	@echo  test             Run all tests with coverage
	@echo  test-unit        Run unit tests only
	@echo  airflow-up       Start Airflow (Docker Compose)
	@echo  airflow-down     Stop Airflow
	@echo  airflow-logs     Tail Airflow logs
	@echo  smoke-test       Run Phase 1 S3 connectivity smoke test
	@echo  tf-init          Terraform init (dev)
	@echo  tf-plan          Terraform plan (dev)
	@echo  tf-apply         Terraform apply (dev)
	@echo  tf-destroy       Terraform destroy (dev)
	@echo  clean            Remove __pycache__ and .pyc files
	@echo.

# ── Python / venv ─────────────────────────────────────────────────────────────
install:
	$(PIP) install --upgrade pip
	$(PIP) install -r requirements.txt

install-dev:
	$(PIP) install ruff black mypy sqlfluff boto3-stubs[s3,comprehend,translate]

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
airflow-up:
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
tf-init:
	cd terraform\environments\dev && terraform init

tf-plan:
	cd terraform\environments\dev && terraform plan

tf-apply:
	cd terraform\environments\dev && terraform apply

tf-destroy:
	cd terraform\environments\dev && terraform destroy

# ── Cleanup ───────────────────────────────────────────────────────────────────
clean:
	for /r . %%d in (__pycache__) do @if exist "%%d" rd /s /q "%%d"
	del /s /q *.pyc 2>nul
	@echo Cleaned.
