#!/usr/bin/env bash
# Worker node bootstrap script.
# Run this on EACH worker EC2 instance (worker1 and worker2).
# Set WORKER_ID=worker1 or WORKER_ID=worker2 before running.
# Idempotent — safe to run multiple times.
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[setup-worker]${NC} $*"; }
info() { echo -e "${BLUE}[setup-worker]${NC} $*"; }
warn() { echo -e "${YELLOW}[setup-worker]${NC} $*"; }
err()  { echo -e "${RED}[setup-worker]${NC} $*" >&2; exit 1; }

WORKER_ID="${WORKER_ID:-worker1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

info "Setting up ${WORKER_ID}..."

# ── Install Docker ────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    log "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "${USER}"
else
    log "Docker already installed."
fi

if ! docker compose version &>/dev/null; then
    sudo apt-get update -qq && sudo apt-get install -y docker-compose-plugin
fi

# ── Load environment ──────────────────────────────────────────────────────────
ENV_FILE="${PROJECT_DIR}/.env"
if [ -f "${ENV_FILE}" ]; then
    set -a; source "${ENV_FILE}"; set +a
else
    warn ".env file not found. Using defaults."
fi

# ── /etc/hosts configuration ──────────────────────────────────────────────────
log "Configuring /etc/hosts..."
for entry in \
    "${MASTER_PRIVATE_IP:-} master" \
    "${WORKER1_PRIVATE_IP:-} worker1" \
    "${WORKER2_PRIVATE_IP:-} worker2"; do
    host_part="${entry##* }"
    ip_part="${entry%% *}"
    if [ -z "${ip_part}" ]; then
        warn "IP for ${host_part} not set in .env — skipping /etc/hosts entry"
        continue
    fi
    if ! grep -qF "${ip_part} ${host_part}" /etc/hosts; then
        echo "${ip_part} ${host_part}" | sudo tee -a /etc/hosts >/dev/null
        log "  Added: ${ip_part} ${host_part}"
    fi
done

# ── Add master's SSH public key ───────────────────────────────────────────────
MASTER_PUBKEY="${MASTER_PUBKEY:-}"
if [ -n "${MASTER_PUBKEY}" ]; then
    log "Adding master SSH public key..."
    mkdir -p "${HOME}/.ssh"
    if ! grep -qF "${MASTER_PUBKEY}" "${HOME}/.ssh/authorized_keys" 2>/dev/null; then
        echo "${MASTER_PUBKEY}" >> "${HOME}/.ssh/authorized_keys"
        chmod 600 "${HOME}/.ssh/authorized_keys"
        log "  Master key added."
    else
        log "  Master key already present."
    fi
else
    warn "MASTER_PUBKEY not set. Copy the master's ~/.ssh/id_rsa.pub to this node's authorized_keys manually."
fi

# ── Build and start worker containers ─────────────────────────────────────────
log "Building worker Docker image..."
cd "${PROJECT_DIR}"
docker build -t hadoop-base:latest   -f docker/Dockerfile.hadoop-base . 2>&1 | tail -5
docker build -t hadoop-worker:latest -f docker/Dockerfile.worker .       2>&1 | tail -5

log "Starting worker containers..."
WORKER_ID="${WORKER_ID}" \
MASTER_HOST="${MASTER_HOST:-master}" \
docker compose -f docker-compose.worker.yml up -d

# ── Verify DataNode started ───────────────────────────────────────────────────
log "Waiting for DataNode to start..."
for i in $(seq 1 30); do
    if curl -sf "http://localhost:9864/" &>/dev/null; then
        log "DataNode is up."
        break
    fi
    warn "Not ready yet ($i/30)... sleeping 5s"
    sleep 5
done

log "=== ${WORKER_ID} Setup Complete ==="
info "  DataNode Web UI:    http://$(hostname -I | awk '{print $1}'):9864"
info "  NodeManager Web UI: http://$(hostname -I | awk '{print $1}'):8042"
info ""
info "Verify on master: hdfs dfsadmin -report | grep 'Live datanodes'"
