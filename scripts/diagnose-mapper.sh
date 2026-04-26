#!/usr/bin/env bash
# Diagnose why mappers emit zero rows against LendingClub CSV.
set -euo pipefail

CSV_PATH="${1:-/tmp/lendingclub/accepted_2007_to_2018Q4.csv}"
SAMPLE_SIZE="${SAMPLE_SIZE:-1000}"

if [[ ! -f "${CSV_PATH}" ]]; then
  echo "[diagnose] CSV not found at ${CSV_PATH}"
  exit 1
fi

echo "[diagnose] Inspecting ${CSV_PATH} (first ${SAMPLE_SIZE} rows)..."
python3 - "${CSV_PATH}" "${SAMPLE_SIZE}" <<'PY'
import csv
import io
import sys
from collections import Counter

path = sys.argv[1]
sample_size = int(sys.argv[2])

status_counts = Counter()
grade_counts = Counter()
ncols_counts = Counter()
short_rows = 0
rows = 0

with open(path, "rb") as raw:
    text = io.TextIOWrapper(raw, encoding="utf-8-sig", errors="replace")
    reader = csv.reader(text)
    for row in reader:
        if not row:
            continue
        if row[0].strip() in ("loan_amnt", "id"):
            continue
        rows += 1
        ncols_counts[len(row)] += 1
        if len(row) <= 21:
            short_rows += 1
            continue
        status_counts[row[14].strip()] += 1
        grade_counts[row[6].strip()] += 1
        if rows >= sample_size:
            break

print(f"[diagnose] sampled_rows={rows}")
print(f"[diagnose] short_rows={short_rows}")
print("[diagnose] top_col_counts=", ncols_counts.most_common(5))
print("[diagnose] top_status=", status_counts.most_common(10))
print("[diagnose] top_grade=", grade_counts.most_common(10))
PY
