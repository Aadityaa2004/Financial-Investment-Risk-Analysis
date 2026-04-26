# ══════════════════════════════════════════════════════════════════════════════
# Financial Investment Risk Analysis — Makefile
# ══════════════════════════════════════════════════════════════════════════════
.DEFAULT_GOAL := help
SHELL := /bin/bash

PROJECT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
RESULTS_DIR := $(PROJECT_DIR)/results

GREEN  := \033[0;32m
YELLOW := \033[1;33m
NC     := \033[0m

define log
  @echo -e "$(GREEN)[make]$(NC) $(1)"
endef

# ── Docker image names ────────────────────────────────────────────────────────
BASE_IMAGE    := hadoop-base:latest
MASTER_IMAGE  := hadoop-master:latest
WORKER_IMAGE  := hadoop-worker:latest

.PHONY: help build build-base build-master build-worker \
        deploy-master deploy-worker \
        upload-data run-jobs fetch-results \
        status clean test-mapreduce logs

## help: Print all targets with descriptions
help:
	@echo ""
	@echo -e "$(GREEN)Financial Investment Risk Analysis — Available Targets$(NC)"
	@echo "══════════════════════════════════════════════════════"
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'
	@echo ""

## build: Build all Docker images (base → master + worker)
build: build-base build-master build-worker

## build-base: Build the shared Hadoop base image
build-base:
	$(call log,"Building hadoop-base image...")
	docker build \
	    -t $(BASE_IMAGE) \
	    -f docker/Dockerfile.hadoop-base \
	    $(PROJECT_DIR)

## build-master: Build the master node image (requires build-base)
build-master: build-base
	$(call log,"Building hadoop-master image...")
	docker build \
	    -t $(MASTER_IMAGE) \
	    -f docker/Dockerfile.master \
	    $(PROJECT_DIR)

## build-worker: Build the worker node image (requires build-base)
build-worker: build-base
	$(call log,"Building hadoop-worker image...")
	docker build \
	    -t $(WORKER_IMAGE) \
	    -f docker/Dockerfile.worker \
	    $(PROJECT_DIR)

## deploy-master: Start all master node services (NameNode + Go services)
deploy-master:
	$(call log,"Starting master node services...")
	docker compose -f $(PROJECT_DIR)/docker-compose.master.yml up -d
	$(call log,"Master node started. Check status with: make status")

## deploy-worker: Start worker node services (DataNode + NodeManager)
deploy-worker:
	$(call log,"Starting worker node services...")
	docker compose -f $(PROJECT_DIR)/docker-compose.worker.yml up -d
	$(call log,"Worker node started.")

## upload-data: Download LendingClub dataset and upload to HDFS
upload-data:
	$(call log,"Uploading LendingClub dataset to HDFS...")
	bash $(PROJECT_DIR)/scripts/upload-dataset.sh

## run-jobs: Run all 4 MapReduce risk analysis jobs sequentially
run-jobs:
	$(call log,"Running all MapReduce jobs...")
	bash $(PROJECT_DIR)/scripts/run-all-jobs.sh

## fetch-results: Pull MapReduce output from HDFS to ./results/
fetch-results:
	$(call log,"Fetching results from HDFS...")
	mkdir -p $(RESULTS_DIR)
	bash $(PROJECT_DIR)/scripts/fetch-results.sh

## status: Show HDFS health, running containers, and job output listing
status:
	@echo ""
	@echo -e "$(GREEN)══ Docker Containers ════════════════════════$(NC)"
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
	@echo ""
	@echo -e "$(GREEN)══ HDFS Report ══════════════════════════════$(NC)"
	@hdfs dfsadmin -report 2>/dev/null || echo "  (HDFS not accessible from this host)"
	@echo ""
	@echo -e "$(GREEN)══ HDFS Output Directories ══════════════════$(NC)"
	@hdfs dfs -ls /user/hadoop/lendingclub/output/ 2>/dev/null || echo "  (no output yet)"
	@echo ""
	@echo -e "$(GREEN)══ YARN Applications ════════════════════════$(NC)"
	@yarn application -list -appStates ALL 2>/dev/null | head -20 || echo "  (YARN not accessible)"

## clean: Stop containers and remove HDFS output directories
clean:
	$(call log,"Stopping containers...")
	docker compose -f $(PROJECT_DIR)/docker-compose.master.yml down 2>/dev/null || true
	docker compose -f $(PROJECT_DIR)/docker-compose.worker.yml down 2>/dev/null || true
	$(call log,"Removing HDFS output directories...")
	hdfs dfs -rm -r -f /user/hadoop/lendingclub/output/ 2>/dev/null || true
	$(call log,"Removing local results...")
	rm -rf $(RESULTS_DIR)

## test-mapreduce: Test all mapper/reducer pairs locally with sample data (no Hadoop needed)
test-mapreduce:
	@echo ""
	@echo -e "$(GREEN)══ Job 1: Default Rate by Loan Grade ════════$(NC)"
	@cat $(PROJECT_DIR)/mapreduce/test-data/sample_loans.csv \
	    | python3 $(PROJECT_DIR)/mapreduce/job1-default-by-grade/mapper.py \
	    | sort \
	    | python3 $(PROJECT_DIR)/mapreduce/job1-default-by-grade/reducer.py
	@echo ""
	@echo -e "$(GREEN)══ Job 2: Default Rate by US State ══════════$(NC)"
	@cat $(PROJECT_DIR)/mapreduce/test-data/sample_loans.csv \
	    | python3 $(PROJECT_DIR)/mapreduce/job2-default-by-state/mapper.py \
	    | sort \
	    | python3 $(PROJECT_DIR)/mapreduce/job2-default-by-state/reducer.py
	@echo ""
	@echo -e "$(GREEN)══ Job 3: Default Rate by Employment ════════$(NC)"
	@cat $(PROJECT_DIR)/mapreduce/test-data/sample_loans.csv \
	    | python3 $(PROJECT_DIR)/mapreduce/job3-default-by-employment/mapper.py \
	    | sort \
	    | python3 $(PROJECT_DIR)/mapreduce/job3-default-by-employment/reducer.py
	@echo ""
	@echo -e "$(GREEN)══ Job 4: Interest Rate vs Default Rate ═════$(NC)"
	@cat $(PROJECT_DIR)/mapreduce/test-data/sample_loans.csv \
	    | python3 $(PROJECT_DIR)/mapreduce/job4-interest-vs-default/mapper.py \
	    | sort \
	    | python3 $(PROJECT_DIR)/mapreduce/job4-interest-vs-default/reducer.py

## logs: Tail logs from all Go services running in the master container
logs:
	$(call log,"Tailing logs from hadoop-master container...")
	docker logs -f hadoop-master 2>&1 | grep -E "(api-gateway|job-orchestrator|result-aggregator|dashboard|ERROR|WARN)" || \
	    docker logs -f hadoop-master
