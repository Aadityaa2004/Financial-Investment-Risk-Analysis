#!/usr/bin/env bash
# Downloads the LendingClub dataset and uploads it to HDFS.
# Requires KAGGLE_USERNAME and KAGGLE_KEY environment variables (or ~/.kaggle/kaggle.json).
# If you downloaded the CSV manually, place it at /tmp/accepted_2007_to_2018Q4.csv and re-run.
# Idempotent — skips upload if file already in HDFS.
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[upload-dataset]${NC} $*"; }
warn() { echo -e "${YELLOW}[upload-dataset]${NC} $*"; }
err()  { echo -e "${RED}[upload-dataset]${NC} $*" >&2; exit 1; }

HDFS_INPUT="${HDFS_INPUT:-/user/hadoop/lendingclub/input}"
LOCAL_DIR="${LOCAL_DIR:-/tmp/lendingclub}"
CSV_FILE="${LOCAL_DIR}/accepted_2007_to_2018Q4.csv"
GZ_FILE="${LOCAL_DIR}/accepted_2007_to_2018Q4.csv.gz"
KAGGLE_DATASET="wordsforthewise/lending-club"

# ── Check HDFS already has the file ───────────────────────────────────────────
if hdfs dfs -test -e "${HDFS_INPUT}/accepted_2007_to_2018Q4.csv" 2>/dev/null; then
    log "Dataset already in HDFS at ${HDFS_INPUT}/accepted_2007_to_2018Q4.csv"
    log "Skipping download. To re-upload, run: hdfs dfs -rm ${HDFS_INPUT}/accepted_2007_to_2018Q4.csv"
    hdfs dfs -ls -h "${HDFS_INPUT}/"
    exit 0
fi

mkdir -p "${LOCAL_DIR}"

# ── Download via Kaggle CLI ───────────────────────────────────────────────────
if [ ! -f "${CSV_FILE}" ] && [ ! -f "${GZ_FILE}" ]; then
    log "Attempting Kaggle CLI download..."

    if [ -n "${KAGGLE_USERNAME:-}" ] && [ -n "${KAGGLE_KEY:-}" ]; then
        mkdir -p "${HOME}/.kaggle"
        echo "{\"username\":\"${KAGGLE_USERNAME}\",\"key\":\"${KAGGLE_KEY}\"}" > "${HOME}/.kaggle/kaggle.json"
        chmod 600 "${HOME}/.kaggle/kaggle.json"
    fi

    if command -v kaggle &>/dev/null; then
        log "Downloading from Kaggle: ${KAGGLE_DATASET}..."
        kaggle datasets download -d "${KAGGLE_DATASET}" \
            --file "accepted_2007_to_2018Q4.csv.gz" \
            -p "${LOCAL_DIR}" --force
    else
        warn "kaggle CLI not found. Installing..."
        pip3 install --quiet kaggle
        kaggle datasets download -d "${KAGGLE_DATASET}" \
            --file "accepted_2007_to_2018Q4.csv.gz" \
            -p "${LOCAL_DIR}" --force
    fi
fi

# ── Decompress if needed ──────────────────────────────────────────────────────
if [ ! -f "${CSV_FILE}" ]; then
    if [ -f "${GZ_FILE}" ]; then
        log "Decompressing ${GZ_FILE}..."
        gunzip -k "${GZ_FILE}"
        log "Decompressed to ${CSV_FILE}"
    else
        err "Neither ${CSV_FILE} nor ${GZ_FILE} found after download attempt."
    fi
fi

CSV_SIZE=$(du -sh "${CSV_FILE}" | cut -f1)
log "Local CSV size: ${CSV_SIZE}"

# ── Upload to HDFS ────────────────────────────────────────────────────────────
log "Creating HDFS input directory..."
hdfs dfs -mkdir -p "${HDFS_INPUT}"

log "Uploading to HDFS (this may take several minutes for a ~500MB file)..."
hdfs dfs -put -f "${CSV_FILE}" "${HDFS_INPUT}/"

# ── Verify ────────────────────────────────────────────────────────────────────
log "Verifying HDFS upload..."
hdfs dfs -ls -h "${HDFS_INPUT}/"
HDFS_ROW_COUNT=$(hdfs dfs -cat "${HDFS_INPUT}/accepted_2007_to_2018Q4.csv" | wc -l)
log "Uploaded file has ${HDFS_ROW_COUNT} lines (including header)."

log "Dataset upload complete."
log "Run: bash scripts/run-all-jobs.sh"
