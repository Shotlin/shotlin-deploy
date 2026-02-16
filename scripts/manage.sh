#!/bin/bash
# ═══════════════════════════════════════════════════════
#  Shotlin — Management Commands v2.0
#  Usage: ./scripts/manage.sh <command>
# ═══════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
cd "${PROJECT_DIR}"

source .env 2>/dev/null || true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

show_help() {
    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║    🛠  SHOTLIN MANAGEMENT CLI v2.0          ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "Usage: ./scripts/manage.sh <command>"
    echo ""
    echo "Commands:"
    echo "  status         Show status of all services"
    echo "  logs           Follow all logs (Ctrl+C to stop)"
    echo "  logs-api       Follow backend API logs only"
    echo "  logs-web       Follow frontend logs only"
    echo "  logs-admin     Follow admin panel logs only"
    echo "  backup         Create an immediate database backup"
    echo "  restore        Restore from a backup file"
    echo "  shell-db       Open PostgreSQL interactive shell"
    echo "  shell-api      Open shell in backend container"
    echo "  seed-admin     Create/reset admin user"
    echo "  migrate        Run database migrations"
    echo "  ssl-check      Check SSL certificate validity"
    echo "  update-cf-ips  Update Cloudflare IP whitelist"
    echo "  update         Pull latest images and redeploy"
    echo "  stop           Stop all services"
    echo "  down           Stop and remove all containers"
    echo "  disk           Show disk usage"
    echo "  clean          Remove unused Docker resources"
    echo "  security       Run security audit"
    echo ""
}

case "${1:-help}" in
    status)
        echo -e "\n${CYAN}═══ Service Status ═══${NC}\n"
        docker compose ps
        echo ""
        echo -e "${CYAN}═══ Resource Usage ═══${NC}\n"
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}" \
            shotlin_postgres shotlin_backend shotlin_frontend shotlin_dashboard shotlin_nginx 2>/dev/null || true
        echo ""
        echo -e "${CYAN}═══ Disk ═══${NC}\n"
        df -h / | awk 'NR==1 || NR==2'
        ;;

    logs)
        docker compose logs -f --tail=100
        ;;

    logs-api)
        docker compose logs -f --tail=100 backend
        ;;

    logs-web)
        docker compose logs -f --tail=100 frontend
        ;;

    logs-admin)
        docker compose logs -f --tail=100 dashboard
        ;;

    backup)
        echo -e "${GREEN}Creating immediate backup...${NC}"
        mkdir -p backups
        TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
        docker compose exec -T postgres pg_dump -U "${POSTGRES_USER}" -Fc "${POSTGRES_DB}" | \
            gzip > "backups/manual_${TIMESTAMP}.sql.gz"
        SIZE=$(du -h "backups/manual_${TIMESTAMP}.sql.gz" | cut -f1)
        echo -e "${GREEN}✅ Backup saved: backups/manual_${TIMESTAMP}.sql.gz (${SIZE})${NC}"
        ;;

    restore)
        if [ -z "${2:-}" ]; then
            echo "Available backups:"
            ls -lh backups/*.sql.gz 2>/dev/null || echo "  No backups found"
            echo ""
            echo "Usage: ./scripts/manage.sh restore <backup-file>"
            exit 1
        fi
        BACKUP_FILE="${2}"
        if [ ! -f "${BACKUP_FILE}" ]; then
            echo -e "${RED}❌ File not found: ${BACKUP_FILE}${NC}"
            exit 1
        fi
        echo -e "${YELLOW}⚠️ WARNING: This will REPLACE your current database!${NC}"
        read -p "Are you sure? Type 'yes' to continue: " -r
        if [ "${REPLY}" != "yes" ]; then
            echo "Aborted."
            exit 0
        fi
        echo "Restoring from ${BACKUP_FILE}..."
        gunzip -c "${BACKUP_FILE}" | docker compose exec -T postgres pg_restore \
            -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" --clean --if-exists
        echo -e "${GREEN}✅ Database restored!${NC}"
        echo "Restarting backend..."
        docker compose restart backend
        ;;

    shell-db)
        docker compose exec postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}"
        ;;

    shell-api)
        docker compose exec backend sh
        ;;

    seed-admin)
        echo "Creating admin user..."
        docker compose exec backend npx ts-node prisma/seed-admin.ts
        echo -e "${GREEN}✅ Admin user created/updated${NC}"
        ;;

    migrate)
        echo "Running database migrations..."
        docker compose exec backend npx prisma migrate deploy
        echo -e "${GREEN}✅ Migrations applied${NC}"
        ;;

    ssl-check)
        echo -e "\n${CYAN}═══ SSL Certificate Status ═══${NC}\n"
        if [ -f "ssl/origin.pem" ]; then
            openssl x509 -in ssl/origin.pem -noout -subject -dates -issuer
            echo ""
            EXPIRY=$(openssl x509 -in ssl/origin.pem -noout -enddate | cut -d= -f2)
            echo -e "  Expires: ${EXPIRY}"
            EXPIRY_EPOCH=$(date -d "${EXPIRY}" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "${EXPIRY}" +%s 2>/dev/null || echo "0")
            NOW_EPOCH=$(date +%s)
            if [ "${EXPIRY_EPOCH}" -gt 0 ]; then
                DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
                echo -e "  Days left: ${DAYS_LEFT}"
            fi
        else
            echo -e "${RED}No certificate found at ssl/origin.pem${NC}"
        fi
        ;;

    update-cf-ips)
        echo "Updating Cloudflare IP ranges..."
        ./scripts/update-cloudflare-ips.sh
        echo "Reloading Nginx..."
        docker compose exec nginx nginx -s reload
        echo -e "${GREEN}✅ Cloudflare IPs updated and Nginx reloaded${NC}"
        ;;

    update)
        echo "Pulling latest images and redeploying..."
        docker compose pull postgres nginx
        docker compose up -d --build --remove-orphans
        docker image prune -f 2>/dev/null || true
        echo -e "${GREEN}✅ Update complete${NC}"
        ;;

    stop)
        docker compose stop
        echo -e "${GREEN}✅ All services stopped${NC}"
        ;;

    down)
        echo -e "${YELLOW}⚠️ This will stop and remove all containers (data is preserved in volumes)${NC}"
        read -p "Continue? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker compose down
            echo -e "${GREEN}✅ All containers removed${NC}"
        fi
        ;;

    disk)
        echo -e "\n${CYAN}═══ Disk Usage ═══${NC}\n"
        echo "System disk:"
        df -h / | awk 'NR==1 || NR==2'
        echo ""
        echo "Docker images:"
        docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | head -20
        echo ""
        echo "Docker volumes:"
        docker system df -v 2>/dev/null | head -20
        echo ""
        echo "Backups:"
        du -sh backups/ 2>/dev/null || echo "  No backups"
        echo ""
        echo "Total Docker disk usage:"
        docker system df 2>/dev/null
        ;;

    clean)
        echo "Cleaning unused Docker resources..."
        docker system prune -f
        docker image prune -f
        docker volume prune -f 2>/dev/null || true
        echo -e "${GREEN}✅ Cleanup complete${NC}"
        echo ""
        echo "Disk after cleanup:"
        df -h / | awk 'NR==1 || NR==2'
        ;;

    security)
        echo -e "\n${CYAN}═══ Security Audit ═══${NC}\n"
        
        echo "1. SSL Certificate:"
        openssl x509 -in ssl/origin.pem -noout -dates 2>/dev/null && echo "   ✅ Valid" || echo "   ❌ Invalid"
        
        echo ""
        echo "2. Open Ports (should only be 22, 80, 443):"
        ss -tlnp 2>/dev/null | grep LISTEN || netstat -tlnp 2>/dev/null | grep LISTEN
        
        echo ""
        echo "3. Firewall Status:"
        sudo ufw status 2>/dev/null || echo "   UFW not available"
        
        echo ""
        echo "4. Failed SSH attempts (last 24h):"
        journalctl -u ssh --since "24 hours ago" 2>/dev/null | grep -c "Failed" || echo "   0"
        
        echo ""
        echo "5. Docker containers running as root:"
        docker ps --format "{{.Names}}" | while read name; do
            USER=$(docker inspect --format='{{.Config.User}}' "$name" 2>/dev/null)
            if [ -z "$USER" ] || [ "$USER" = "root" ] || [ "$USER" = "0" ]; then
                echo "   ⚠️ ${name}: running as root"
            else
                echo "   ✅ ${name}: running as ${USER}"
            fi
        done
        
        echo ""
        echo "6. Environment file permissions:"
        PERM=$(stat -c %a .env 2>/dev/null || stat -f %A .env 2>/dev/null)
        if [ "${PERM}" = "600" ]; then
            echo "   ✅ .env: ${PERM} (secure)"
        else
            echo "   ⚠️ .env: ${PERM} (should be 600 — run: chmod 600 .env)"
        fi
        ;;

    help|--help|-h)
        show_help
        ;;

    *)
        echo -e "${RED}Unknown command: ${1}${NC}"
        show_help
        exit 1
        ;;
esac
