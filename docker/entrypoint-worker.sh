#!/usr/bin/env bash
# Worker node entrypoint: starts SSH + Hadoop DataNode + NodeManager.
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[worker]${NC} $*"; }
warn() { echo -e "${YELLOW}[worker]${NC} $*"; }

WORKER_ID="${WORKER_ID:-worker}"
MASTER="${MASTER_HOST:-master}"

# Add local fallback host mappings when explicit DNS/hosts entries are absent.
ensure_host_entry() {
    local host="$1"
    if ! getent hosts "${host}" >/dev/null 2>&1; then
        printf '\n127.0.0.1 %s\n' "${host}" >> /etc/hosts
        warn "[$WORKER_ID] Added fallback /etc/hosts entry: ${host} -> 127.0.0.1"
    fi
}

ensure_host_entry "master"
ensure_host_entry "worker1"
ensure_host_entry "worker2"

# ── SSH ──────────────────────────────────────────────────────────────────────
log "[$WORKER_ID] Starting SSH daemon..."
service ssh start || /usr/sbin/sshd

# ── Wait for master NameNode to be reachable ──────────────────────────────────
log "[$WORKER_ID] Waiting for NameNode at ${MASTER}:9000..."
for i in $(seq 1 60); do
    if nc -z "${MASTER}" 9000 2>/dev/null; then
        log "[$WORKER_ID] NameNode reachable."
        break
    fi
    warn "[$WORKER_ID] Not ready yet (attempt $i/60), sleeping 5s..."
    sleep 5
done

# ── Start DataNode ────────────────────────────────────────────────────────────
log "[$WORKER_ID] Starting DataNode..."
hdfs --daemon start datanode

# ── Start NodeManager ─────────────────────────────────────────────────────────
log "[$WORKER_ID] Starting NodeManager..."
yarn --daemon start nodemanager

log "[$WORKER_ID] Worker daemons started."
log "  DataNode Web UI:    http://\$(hostname -I | awk '{print \$1}'):9864"
log "  NodeManager Web UI: http://\$(hostname -I | awk '{print \$1}'):8042"

# Keep container alive
tail -f /opt/hadoop/logs/*.log 2>/dev/null || tail -f /dev/null
