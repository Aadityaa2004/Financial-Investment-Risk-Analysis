#!/usr/bin/env bash
# Master node entrypoint: starts SSH, formats HDFS (once), starts Hadoop daemons,
# then launches all four Go microservices in the background.
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[master]${NC} $*"; }
warn() { echo -e "${YELLOW}[master]${NC} $*"; }
err()  { echo -e "${RED}[master]${NC} $*" >&2; }

# ── SSH ──────────────────────────────────────────────────────────────────────
log "Starting SSH daemon..."
service ssh start || /usr/sbin/sshd

# ── HDFS format (idempotent) ──────────────────────────────────────────────────
NAMENODE_DIR="${NAMENODE_DIR:-/hadoop/hdfs/namenode}"
if [ ! -d "${NAMENODE_DIR}/current" ]; then
    warn "Formatting NameNode (first run only)..."
    hdfs namenode -format -force -nonInteractive
    log "NameNode formatted."
else
    log "NameNode already formatted — skipping format."
fi

# ── Start Hadoop daemons ──────────────────────────────────────────────────────
log "Starting HDFS daemons..."
start-dfs.sh

log "Starting YARN daemons..."
start-yarn.sh

log "Starting MapReduce JobHistory server..."
mapred --daemon start historyserver

# ── Wait for NameNode to leave safe mode ─────────────────────────────────────
log "Waiting for NameNode to exit safe mode..."
for i in $(seq 1 30); do
    if hdfs dfsadmin -safemode get 2>/dev/null | grep -q "OFF"; then
        log "NameNode is out of safe mode."
        break
    fi
    warn "Safe mode still ON (attempt $i/30)... waiting 5s"
    sleep 5
done

# ── Create HDFS directories ───────────────────────────────────────────────────
log "Creating HDFS directories..."
hdfs dfs -mkdir -p /user/hadoop/lendingclub/input  || true
hdfs dfs -mkdir -p /user/hadoop/lendingclub/output || true
hdfs dfs -chmod -R 777 /user/hadoop               || true

# ── Start Go microservices ────────────────────────────────────────────────────
log "Starting result-aggregator on :${AGGREGATOR_PORT:-8082}..."
/usr/local/bin/result-aggregator &

log "Starting job-orchestrator on :${ORCHESTRATOR_PORT:-8081}..."
/usr/local/bin/job-orchestrator &

log "Starting api-gateway on :${API_GATEWAY_PORT:-8080}..."
/usr/local/bin/api-gateway &

log "Starting dashboard on :${DASHBOARD_PORT:-3000}..."
/usr/local/bin/dashboard &

log "Master node fully started."
log "  HDFS Web UI:       http://\$(hostname -I | awk '{print \$1}'):9870"
log "  YARN Web UI:       http://\$(hostname -I | awk '{print \$1}'):8088"
log "  API Gateway:       http://\$(hostname -I | awk '{print \$1}'):${API_GATEWAY_PORT:-8080}"
log "  Risk Dashboard:    http://\$(hostname -I | awk '{print \$1}'):${DASHBOARD_PORT:-3000}"

# Keep container alive
tail -f /opt/hadoop/logs/*.log 2>/dev/null || tail -f /dev/null
