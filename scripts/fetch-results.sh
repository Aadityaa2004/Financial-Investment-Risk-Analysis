#!/usr/bin/env bash
# Pulls MapReduce output from HDFS to ./results/ on the local filesystem.
# Idempotent — overwrites existing results.
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[fetch-results]${NC} $*"; }
warn() { echo -e "${YELLOW}[fetch-results]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
RESULTS_DIR="${PROJECT_DIR}/results"
HDFS_OUTPUT_BASE="${HDFS_OUTPUT_BASE:-/user/hadoop/lendingclub/output}"

mkdir -p "${RESULTS_DIR}"

declare -A JOB_LABELS=(
    ["job1-grade"]="job1_default_by_grade.tsv"
    ["job2-state"]="job2_default_by_state.tsv"
    ["job3-employment"]="job3_default_by_employment.tsv"
    ["job4-interest"]="job4_interest_vs_default.tsv"
)

for hdfs_dir in "${!JOB_LABELS[@]}"; do
    local_file="${RESULTS_DIR}/${JOB_LABELS[$hdfs_dir]}"
    hdfs_path="${HDFS_OUTPUT_BASE}/${hdfs_dir}"

    if hdfs dfs -test -e "${hdfs_path}" 2>/dev/null; then
        log "Fetching ${hdfs_dir} → ${local_file}..."
        hdfs dfs -cat "${hdfs_path}/part-*" > "${local_file}"
        ROWS=$(wc -l < "${local_file}")
        log "  Written ${ROWS} rows."
    else
        warn "HDFS path not found: ${hdfs_path} (job may not have run yet)"
    fi
done

log "=== Results saved to ${RESULTS_DIR}/ ==="
ls -lh "${RESULTS_DIR}/"
