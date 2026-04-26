#!/usr/bin/env bash
# Generates ~/.ssh/config entries for the three EC2 nodes.
# Reads IPs from .env file in the project root.
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[ssh-config-helper]${NC} $*"; }
warn() { echo -e "${YELLOW}[ssh-config-helper]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$(dirname "${SCRIPT_DIR}")/.env"

if [ ! -f "${ENV_FILE}" ]; then
    warn ".env file not found. Create it from .env.example and fill in public IPs."
    exit 1
fi
set -a; source "${ENV_FILE}"; set +a

SSH_KEY="${SSH_KEY_PATH:-${HOME}/.ssh/id_rsa}"
SSH_USER="${SSH_USER:-ubuntu}"

if [ -z "${MASTER_PUBLIC_IP:-}" ] || [ -z "${WORKER1_PUBLIC_IP:-}" ] || [ -z "${WORKER2_PUBLIC_IP:-}" ]; then
    warn "One or more public IPs not set in .env. Fill in MASTER_PUBLIC_IP, WORKER1_PUBLIC_IP, WORKER2_PUBLIC_IP."
    exit 1
fi

SSH_CONFIG_BLOCK=$(cat <<EOF

# ── Hadoop Risk Analysis Cluster ──────────────────────────────────────────────
Host hadoop-master
    HostName ${MASTER_PUBLIC_IP}
    User ${SSH_USER}
    IdentityFile ${SSH_KEY}
    StrictHostKeyChecking no

Host hadoop-worker1
    HostName ${WORKER1_PUBLIC_IP}
    User ${SSH_USER}
    IdentityFile ${SSH_KEY}
    StrictHostKeyChecking no

Host hadoop-worker2
    HostName ${WORKER2_PUBLIC_IP}
    User ${SSH_USER}
    IdentityFile ${SSH_KEY}
    StrictHostKeyChecking no
EOF
)

SSH_CONFIG="${HOME}/.ssh/config"
mkdir -p "${HOME}/.ssh"
touch "${SSH_CONFIG}"
chmod 600 "${SSH_CONFIG}"

if grep -q "hadoop-master" "${SSH_CONFIG}" 2>/dev/null; then
    warn "SSH config entries already present. Remove them manually if you want to regenerate."
else
    echo "${SSH_CONFIG_BLOCK}" >> "${SSH_CONFIG}"
    log "SSH config entries added to ${SSH_CONFIG}"
fi

log "Test connections with:"
log "  ssh hadoop-master hostname"
log "  ssh hadoop-worker1 hostname"
log "  ssh hadoop-worker2 hostname"
