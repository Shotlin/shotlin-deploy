#!/bin/bash
# ═══════════════════════════════════════════════════════
#  Shotlin — One-Command Production Deploy v2.0
#  AWS EC2 + Cloudflare | Optimized for 2vCPU / 2GB RAM
# ═══════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
cd "${PROJECT_DIR}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

banner() {
    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║     🚀 SHOTLIN DEPLOY v2.0 (AWS+CF)       ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
}

log()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; exit 1; }
info()  { echo -e "${BLUE}[→]${NC} $*"; }

# Parse arguments
BUILD_FLAG=""
RESTART_FLAG=""
for arg in "$@"; do
    case $arg in
        --build)   BUILD_FLAG="--build" ;;
        --restart) RESTART_FLAG="true" ;;
        --help)
            banner
            echo "Usage: ./scripts/deploy.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --build     Force rebuild all images"
            echo "  --restart   Restart all services (no rebuild)"
            echo "  --help      Show this help"
            exit 0
            ;;
    esac
done

banner

# ─── Pre-flight checks ───
info "Running pre-flight checks..."

# Check .env
if [ ! -f .env ]; then
    error ".env file not found! Run: cp .env.example .env && nano .env"
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    error "Docker is not installed!"
fi

if ! docker compose version &> /dev/null; then
    error "Docker Compose is not available!"
fi

# Check for default passwords
source .env
if [ "${POSTGRES_PASSWORD:-}" = "CHANGE_ME_TO_A_STRONG_PASSWORD_HERE" ]; then
    error "You haven't changed POSTGRES_PASSWORD in .env — DO NOT use default passwords!"
fi

if [ "${JWT_SECRET:-}" = "CHANGE_ME_GENERATE_WITH_openssl_rand_hex_32" ]; then
    error "You haven't set JWT_SECRET in .env — Run: openssl rand -hex 32"
fi

# Check SSL certificates
if [ ! -f "ssl/origin.pem" ] || [ ! -f "ssl/origin-key.pem" ]; then
    error "SSL certificates not found! Run: ./scripts/init-ssl.sh"
fi

log "Pre-flight checks passed"

# ─── Disk space check ───
DISK_FREE=$(df -BM / | awk 'NR==2 {gsub("M",""); print $4}')
if [ "${DISK_FREE}" -lt 1024 ]; then
    warn "Low disk space: ${DISK_FREE}MB free (need >1GB)"
    warn "Run: ./scripts/manage.sh clean"
fi

# ─── Restart only ───
if [ "${RESTART_FLAG}" = "true" ]; then
    info "Restarting all services..."
    docker compose restart
    log "All services restarted!"
    exit 0
fi

# ─── Pull latest base images ───
info "Pulling latest base images..."
docker compose pull postgres nginx 2>/dev/null || true

# ─── Build & Deploy ───
info "Building and deploying all services..."
docker compose up -d ${BUILD_FLAG} --remove-orphans

# ─── Cleanup dangling images (save SSD space) ───
info "Cleaning up old images..."
docker image prune -f 2>/dev/null || true

# ─── Wait for services ───
info "Waiting for services to become healthy..."
sleep 15

# Check health
check_service() {
    local service=$1
    local container="shotlin_${service}"
    local running=$(docker inspect --format='{{.State.Running}}' "${container}" 2>/dev/null || echo "false")
    local health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "${container}" 2>/dev/null || echo "unknown")
    
    if [ "${running}" = "true" ]; then
        log "${service}: running (${health})"
    else
        warn "${service}: NOT RUNNING"
    fi
}

echo ""
echo "  ┌──────────────────────────────────┐"
echo "  │         Service Status           │"
echo "  ├──────────────────────────────────┤"
check_service "postgres"
check_service "backend"
check_service "frontend"
check_service "dashboard"
check_service "nginx"
echo "  └──────────────────────────────────┘"

# ─── Memory usage ───
echo ""
info "Memory usage:"
docker stats --no-stream --format "  {{.Name}}: {{.MemUsage}}" \
    shotlin_postgres shotlin_backend shotlin_frontend shotlin_dashboard shotlin_nginx 2>/dev/null || true

# ─── Summary ───
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ Deployment Complete!${NC}"
echo ""
echo -e "  🌐 Frontend:    https://${DOMAIN}"
echo -e "  📊 Admin Panel: https://adminpanel.${DOMAIN}"
echo -e "  🔌 API:         https://api.${DOMAIN}"
echo -e ""
echo -e "  📋 Logs:        docker compose logs -f"
echo -e "  🔄 Restart:     ./scripts/deploy.sh --restart"
echo -e "  🔨 Rebuild:     ./scripts/deploy.sh --build"
echo -e "  💾 Backup now:  ./scripts/manage.sh backup"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
