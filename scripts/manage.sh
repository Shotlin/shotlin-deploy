#!/bin/bash
# ═══════════════════════════════════════════════════════
#  Shotlin — Management Commands
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
    echo "  ║      🛠  SHOTLIN MANAGEMENT CLI            ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "Usage: ./scripts/manage.sh <command>"
    echo ""
    echo "Commands:"
    echo "  status       Show status of all services"
    echo "  logs         Follow all logs (Ctrl+C to stop)"
    echo "  logs-api     Follow backend API logs only"
    echo "  logs-web     Follow frontend logs only"
    echo "  logs-crm     Follow dashboard logs only"
    echo "  backup       Create an immediate database backup"
    echo "  restore      Restore from a backup file"
    echo "  shell-db     Open PostgreSQL interactive shell"
    echo "  shell-api    Open shell in backend container"
    echo "  seed-admin   Create/reset admin user"
    echo "  migrate      Run database migrations"
    echo "  ssl-status   Check SSL certificate status"
    echo "  ssl-renew    Force SSL certificate renewal"
    echo "  update       Pull latest images and redeploy"
    echo "  stop         Stop all services"
    echo "  down         Stop and remove all containers"
    echo "  disk         Show disk usage"
    echo "  clean        Remove unused Docker resources"
    echo ""
}

case "${1:-help}" in
    status)
        echo -e "\n${CYAN}═══ Service Status ═══${NC}\n"
        docker compose ps
        echo ""
        echo -e "${CYAN}═══ Resource Usage ═══${NC}\n"
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" \
            shotlin_postgres shotlin_backend shotlin_frontend shotlin_dashboard shotlin_nginx 2>/dev/null || true
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

    logs-crm)
        docker compose logs -f --tail=100 dashboard
        ;;

    backup)
        echo -e "${GREEN}Creating immediate backup...${NC}"
        TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
        docker compose exec postgres pg_dump -U "${POSTGRES_USER}" "${POSTGRES_DB}" -Fc | \
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

    ssl-status)
        echo -e "\n${CYAN}═══ SSL Certificate Status ═══${NC}\n"
        docker compose run --rm certbot certificates
        ;;

    ssl-renew)
        echo "Forcing SSL renewal..."
        docker compose run --rm certbot renew --force-renewal
        docker compose exec nginx nginx -s reload
        echo -e "${GREEN}✅ SSL certificates renewed and Nginx reloaded${NC}"
        ;;

    update)
        echo "Pulling latest images and redeploying..."
        docker compose pull
        docker compose up -d --build --remove-orphans
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
        echo "Docker images:"
        docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep -i shotlin || echo "  Not built yet"
        echo ""
        echo "Docker volumes:"
        docker volume ls --format "table {{.Name}}\t{{.Driver}}" | grep -i shotlin || echo "  None"
        echo ""
        echo "Backups:"
        du -sh backups/ 2>/dev/null || echo "  No backups"
        ;;

    clean)
        echo "Cleaning unused Docker resources..."
        docker system prune -f
        docker image prune -f
        echo -e "${GREEN}✅ Cleanup complete${NC}"
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
