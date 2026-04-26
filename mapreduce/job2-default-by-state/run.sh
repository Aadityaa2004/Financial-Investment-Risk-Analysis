#!/usr/bin/env bash
# Submits Job 2 (Default Rate by US State) to Hadoop YARN via Streaming.
set -euo pipefail

HDFS_INPUT="${HDFS_INPUT:-/user/hadoop/lendingclub/input}"
HDFS_OUTPUT="${HDFS_OUTPUT_BASE:-/user/hadoop/lendingclub/output}/job2-state"
STREAMING_JAR=$(find "${HADOOP_HOME}/share/hadoop/tools/lib" -name "hadoop-streaming-*.jar" | head -1)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[job2] Removing stale output (if any)..."
hdfs dfs -rm -r -f "${HDFS_OUTPUT}" || true

echo "[job2] Submitting Default Rate by US State job..."
hadoop jar "${STREAMING_JAR}" \
  -D mapreduce.job.name="RiskAnalysis-Job2-DefaultByState" \
  -D mapreduce.job.reduces=1 \
  -input "${HDFS_INPUT}" \
  -output "${HDFS_OUTPUT}" \
  -mapper  "python3 mapper.py" \
  -reducer "python3 reducer.py" \
  -file    "${SCRIPT_DIR}/mapper.py" \
  -file    "${SCRIPT_DIR}/reducer.py"

echo "[job2] Completed. Output at ${HDFS_OUTPUT}"
echo "[job2] Row count: $(hdfs dfs -cat "${HDFS_OUTPUT}/part-*" | wc -l)"
