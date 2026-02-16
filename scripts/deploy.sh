#!/bin/bash
# ═══════════════════════════════════════════════════════
#  Shotlin — One-Command Production Deploy
#  Usage: ./scripts/deploy.sh [--build] [--restart]
# ═══════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
cd "${PROJECT_DIR}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

banner() {
    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║         🚀 SHOTLIN DEPLOY v1.0            ║"
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
            echo ""
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

log "Pre-flight checks passed"

# ─── Check SSL ───
if [ ! -d "certbot/conf/live/${DOMAIN}" ]; then
    warn "SSL certificates not found!"
    info "Run './scripts/init-ssl.sh' first to set up SSL"
    echo ""
    read -p "Continue without SSL (HTTP only)? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
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
docker compose pull postgres nginx certbot watchtower 2>/dev/null || true

# ─── Build & Deploy ───
info "Building and deploying all services..."
docker compose up -d ${BUILD_FLAG} --remove-orphans

# ─── Wait for services ───
info "Waiting for services to become healthy..."
sleep 10

# Check health
check_service() {
    local service=$1
    local status=$(docker inspect --format='{{.State.Health.Status}}' "shotlin_${service}" 2>/dev/null || echo "unknown")
    if [ "${status}" = "healthy" ] || [ "${status}" = "unknown" ]; then
        log "${service}: ${status}"
    else
        warn "${service}: ${status}"
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

# ─── Summary ───
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ Deployment Complete!${NC}"
echo ""
echo -e "  🌐 Frontend:   https://${DOMAIN}"
echo -e "  📊 Dashboard:  https://crm.${DOMAIN}"
echo -e "  🔌 API:        https://api.${DOMAIN}"
echo -e ""
echo -e "  📋 Logs:       docker compose logs -f"
echo -e "  🔄 Restart:    ./scripts/deploy.sh --restart"
echo -e "  🔨 Rebuild:    ./scripts/deploy.sh --build"
echo -e "  💾 Backup now: ./scripts/manage.sh backup"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
