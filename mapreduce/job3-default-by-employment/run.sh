#!/usr/bin/env bash
# Submits Job 3 (Default Rate by Employment Length) to Hadoop YARN via Streaming.
set -euo pipefail

HDFS_INPUT="${HDFS_INPUT:-/user/hadoop/lendingclub/input}"
HDFS_OUTPUT="${HDFS_OUTPUT_BASE:-/user/hadoop/lendingclub/output}/job3-employment"
STREAMING_JAR=$(find "${HADOOP_HOME}/share/hadoop/tools/lib" -name "hadoop-streaming-*.jar" | head -1)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[job3] Removing stale output (if any)..."
hdfs dfs -rm -r -f "${HDFS_OUTPUT}" || true

echo "[job3] Submitting Default Rate by Employment Length job..."
hadoop jar "${STREAMING_JAR}" \
  -D mapreduce.job.name="RiskAnalysis-Job3-DefaultByEmployment" \
  -D mapreduce.job.reduces=1 \
  -input "${HDFS_INPUT}" \
  -output "${HDFS_OUTPUT}" \
  -mapper  "python3 mapper.py" \
  -reducer "python3 reducer.py" \
  -file    "${SCRIPT_DIR}/mapper.py" \
  -file    "${SCRIPT_DIR}/reducer.py"

echo "[job3] Completed. Output at ${HDFS_OUTPUT}"
echo "[job3] Row count: $(hdfs dfs -cat "${HDFS_OUTPUT}/part-*" | wc -l)"
