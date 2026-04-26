#!/usr/bin/env bash
# Runs all four MapReduce risk analysis jobs sequentially.
# Prints per-job timing and output row counts.
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${GREEN}[run-jobs]${NC} $*"; }
info()    { echo -e "${BLUE}[run-jobs]${NC} $*"; }
warn()    { echo -e "${YELLOW}[run-jobs]${NC} $*"; }
err()     { echo -e "${RED}[run-jobs]${NC} $*" >&2; exit 1; }
divider() { echo -e "${BLUE}────────────────────────────────────────────────${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

export HDFS_INPUT="${HDFS_INPUT:-/user/hadoop/lendingclub/input}"
export HDFS_OUTPUT_BASE="${HDFS_OUTPUT_BASE:-/user/hadoop/lendingclub/output}"
export HADOOP_HOME="${HADOOP_HOME:-/opt/hadoop}"

# ── Pre-flight checks ─────────────────────────────────────────────────────────
command -v hadoop >/dev/null || err "hadoop command not found. Is Hadoop installed and in PATH?"
command -v hdfs   >/dev/null || err "hdfs command not found."

log "Checking HDFS input..."
if ! hdfs dfs -test -e "${HDFS_INPUT}" 2>/dev/null; then
    err "HDFS input path not found: ${HDFS_INPUT}. Run upload-dataset.sh first."
fi

INPUT_COUNT=$(hdfs dfs -ls "${HDFS_INPUT}/" | grep -c "^-" || true)
log "Input directory has ${INPUT_COUNT} file(s)."

TOTAL_START=$(date +%s)
declare -A JOB_TIMES

# ── Job runner helper ─────────────────────────────────────────────────────────
run_job() {
    local job_num="$1"
    local job_dir="$2"
    local job_label="$3"

    divider
    info "Starting Job ${job_num}: ${job_label}"
    local start
    start=$(date +%s)

    bash "${PROJECT_DIR}/mapreduce/${job_dir}/run.sh"

    local elapsed=$(( $(date +%s) - start ))
    JOB_TIMES["job${job_num}"]="${elapsed}"
    log "Job ${job_num} finished in ${elapsed}s."
}

# ── Run all four jobs ─────────────────────────────────────────────────────────
run_job 1 "job1-default-by-grade"      "Default Rate by Loan Grade"
run_job 2 "job2-default-by-state"      "Default Rate by US State"
run_job 3 "job3-default-by-employment" "Default Rate by Employment Length"
run_job 4 "job4-interest-vs-default"   "Interest Rate vs Default Rate"

# ── Summary ───────────────────────────────────────────────────────────────────
TOTAL_ELAPSED=$(( $(date +%s) - TOTAL_START ))
divider
log "=== All Jobs Completed in ${TOTAL_ELAPSED}s ==="
for i in 1 2 3 4; do
    log "  Job ${i}: ${JOB_TIMES[job${i}]}s"
done

divider
log "Output directories:"
hdfs dfs -ls "${HDFS_OUTPUT_BASE}/"

divider
log "Sample output from each job:"

for job_dir in job1-grade job2-state job3-employment job4-interest; do
    info "--- ${job_dir} ---"
    hdfs dfs -cat "${HDFS_OUTPUT_BASE}/${job_dir}/part-*" | head -10
done

log "Run 'make fetch-results' to copy results to ./results/"
