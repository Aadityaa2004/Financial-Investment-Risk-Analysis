#!/usr/bin/env bash
# Submits Job 4 (Interest Rate vs Default Rate by Grade) to Hadoop YARN via Streaming.
set -euo pipefail

HDFS_INPUT="${HDFS_INPUT:-/user/hadoop/lendingclub/input}"
HDFS_OUTPUT="${HDFS_OUTPUT_BASE:-/user/hadoop/lendingclub/output}/job4-interest"
STREAMING_JAR=$(find "${HADOOP_HOME}/share/hadoop/tools/lib" -name "hadoop-streaming-*.jar" | head -1)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[job4] Removing stale output (if any)..."
hdfs dfs -rm -r -f "${HDFS_OUTPUT}" || true

echo "[job4] Submitting Interest Rate vs Default Rate by Grade job..."
hadoop jar "${STREAMING_JAR}" \
  -D mapreduce.job.name="RiskAnalysis-Job4-InterestVsDefault" \
  -D mapreduce.job.reduces=1 \
  -input "${HDFS_INPUT}" \
  -output "${HDFS_OUTPUT}" \
  -mapper  "python3 mapper.py" \
  -reducer "python3 reducer.py" \
  -file    "${SCRIPT_DIR}/mapper.py" \
  -file    "${SCRIPT_DIR}/reducer.py"

echo "[job4] Completed. Output at ${HDFS_OUTPUT}"
echo "[job4] Row count: $(hdfs dfs -cat "${HDFS_OUTPUT}/part-*" | wc -l)"
