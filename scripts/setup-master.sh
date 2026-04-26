#!/usr/bin/env bash
# Full master node bootstrap script.
# Idempotent — safe to run multiple times.
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[setup-master]${NC} $*"; }
info() { echo -e "${BLUE}[setup-master]${NC} $*"; }
warn() { echo -e "${YELLOW}[setup-master]${NC} $*"; }
err()  { echo -e "${RED}[setup-master]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

# ── Dependency checks ─────────────────────────────────────────────────────────
info "Checking prerequisites..."
command -v curl  >/dev/null || err "curl not found. Install with: sudo apt-get install curl"
command -v git   >/dev/null || warn "git not found — install with: sudo apt-get install git"

# ── Install Docker ────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    log "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "${USER}"
    log "Docker installed. You may need to log out and back in for group changes."
else
    log "Docker already installed: $(docker --version)"
fi

if ! command -v docker &>/dev/null; then
    err "Docker installation failed."
fi

# Install Docker Compose plugin if missing
if ! docker compose version &>/dev/null; then
    log "Installing Docker Compose plugin..."
    sudo apt-get update -qq
    sudo apt-get install -y docker-compose-plugin
fi
log "Docker Compose: $(docker compose version)"

# ── Load environment ──────────────────────────────────────────────────────────
ENV_FILE="${PROJECT_DIR}/.env"
if [ ! -f "${ENV_FILE}" ]; then
    if [ -f "${PROJECT_DIR}/.env.example" ]; then
        warn ".env not found — copying from .env.example. EDIT IT before continuing!"
        cp "${PROJECT_DIR}/.env.example" "${ENV_FILE}"
    else
        err ".env file not found. Create it from .env.example."
    fi
fi
set -a; source "${ENV_FILE}"; set +a

# ── /etc/hosts configuration ──────────────────────────────────────────────────
configure_hosts() {
    local master_ip="${MASTER_PRIVATE_IP:-}"
    local worker1_ip="${WORKER1_PRIVATE_IP:-}"
    local worker2_ip="${WORKER2_PRIVATE_IP:-}"

    if [ -z "${master_ip}" ] || [ -z "${worker1_ip}" ] || [ -z "${worker2_ip}" ]; then
        warn "MASTER_PRIVATE_IP / WORKER1_PRIVATE_IP / WORKER2_PRIVATE_IP not set in .env"
        warn "Skipping /etc/hosts configuration. Set these variables and re-run."
        return
    fi

    log "Configuring /etc/hosts..."
    for entry in \
        "${master_ip} master" \
        "${worker1_ip} worker1" \
        "${worker2_ip} worker2"; do
        if ! grep -qF "${entry}" /etc/hosts; then
            echo "${entry}" | sudo tee -a /etc/hosts >/dev/null
            log "  Added: ${entry}"
        else
            log "  Already present: ${entry}"
        fi
    done
}
configure_hosts

# ── SSH key exchange ──────────────────────────────────────────────────────────
log "Setting up SSH keys..."
if [ ! -f "${HOME}/.ssh/id_rsa" ]; then
    ssh-keygen -t rsa -P '' -f "${HOME}/.ssh/id_rsa"
fi

for node in worker1 worker2; do
    if [ -n "${WORKER1_PUBLIC_IP:-}" ] || [ -n "${WORKER2_PUBLIC_IP:-}" ]; then
        NODE_IP_VAR="${node^^}_PUBLIC_IP"
        NODE_IP="${!NODE_IP_VAR:-}"
        if [ -n "${NODE_IP}" ]; then
            log "Copying SSH key to ${node} (${NODE_IP})..."
            ssh-copy-id -o StrictHostKeyChecking=no -i "${HOME}/.ssh/id_rsa.pub" "ubuntu@${NODE_IP}" || \
                warn "Could not auto-copy key to ${node}. Copy manually: ssh-copy-id ubuntu@${NODE_IP}"
        fi
    fi
done

# ── Build and start Docker containers ─────────────────────────────────────────
log "Building Docker images (this takes ~10 minutes on first run)..."
cd "${PROJECT_DIR}"
docker build -t hadoop-base:latest -f docker/Dockerfile.hadoop-base . 2>&1 | tail -5
docker build -t hadoop-master:latest -f docker/Dockerfile.master .    2>&1 | tail -5

log "Starting master node containers..."
docker compose -f docker-compose.master.yml up -d

# ── Wait for NameNode WebHDFS ─────────────────────────────────────────────────
log "Waiting for HDFS NameNode to become healthy..."
for i in $(seq 1 60); do
    if curl -sf "http://localhost:9870/webhdfs/v1/?op=LISTSTATUS" &>/dev/null; then
        log "NameNode is healthy."
        break
    fi
    warn "Not ready yet (attempt $i/60)... sleeping 10s"
    sleep 10
done

# ── Status summary ────────────────────────────────────────────────────────────
log "=== Master Node Setup Complete ==="
info "  HDFS Web UI:       http://$(curl -sf http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || hostname -I | awk '{print $1}'):9870"
info "  YARN Web UI:       http://$(curl -sf http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || hostname -I | awk '{print $1}'):8088"
info "  API Gateway:       http://$(curl -sf http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || hostname -I | awk '{print $1}'):8080"
info "  Risk Dashboard:    http://$(curl -sf http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || hostname -I | awk '{print $1}'):3000"
info ""
info "Next steps:"
info "  1. Run setup-worker.sh on each worker EC2 instance"
info "  2. Run upload-dataset.sh to load the LendingClub data into HDFS"
info "  3. Run run-all-jobs.sh to execute the MapReduce analysis"
