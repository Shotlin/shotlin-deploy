#!/bin/bash
# ═══════════════════════════════════════════════════════
#  Shotlin — SSL Certificate Initialization
#  Run this ONCE on first deployment to get Let's Encrypt certificates
# ═══════════════════════════════════════════════════════

set -euo pipefail

# ─── Load environment ───
if [ ! -f .env ]; then
    echo "❌ .env file not found! Copy .env.example to .env and fill in your values."
    exit 1
fi

source .env

DOMAIN="${DOMAIN:?DOMAIN is not set in .env}"
SSL_EMAIL="${SSL_EMAIL:?SSL_EMAIL is not set in .env}"

echo "═══════════════════════════════════════════════════"
echo "  Shotlin SSL Setup"
echo "  Domain: ${DOMAIN}"
echo "  Email:  ${SSL_EMAIL}"
echo "═══════════════════════════════════════════════════"
echo ""

# ─── Step 1: Create required directories ───
echo "📁 Creating directories..."
mkdir -p certbot/conf certbot/www nginx/conf.d backups

# ─── Step 2: Download recommended TLS parameters ───
echo "🔐 Downloading TLS parameters..."
if [ ! -f "certbot/conf/options-ssl-nginx.conf" ]; then
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf \
        > certbot/conf/options-ssl-nginx.conf
fi

if [ ! -f "certbot/conf/ssl-dhparams.pem" ]; then
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem \
        > certbot/conf/ssl-dhparams.pem
fi

# ─── Step 3: Create temporary self-signed cert ───
echo "📜 Creating temporary self-signed certificate..."
CERT_DIR="certbot/conf/live/${DOMAIN}"
mkdir -p "${CERT_DIR}"

if [ ! -f "${CERT_DIR}/fullchain.pem" ]; then
    openssl req -x509 -nodes -newkey rsa:4096 \
        -days 1 \
        -keyout "${CERT_DIR}/privkey.pem" \
        -out "${CERT_DIR}/fullchain.pem" \
        -subj "/CN=${DOMAIN}" \
        2>/dev/null
    echo "   ✅ Temporary cert created"
fi

# ─── Step 4: Start nginx with temporary cert ───
echo "🌐 Starting Nginx with temporary certificate..."
docker compose up -d nginx
sleep 5

# ─── Step 5: Get real Let's Encrypt certificate ───
echo "🔒 Requesting Let's Encrypt certificate..."
echo "   Domains: ${DOMAIN}, www.${DOMAIN}, api.${DOMAIN}, crm.${DOMAIN}"

# Delete temporary cert
rm -f "${CERT_DIR}/fullchain.pem" "${CERT_DIR}/privkey.pem"
rmdir "${CERT_DIR}" 2>/dev/null || true

docker compose run --rm certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email "${SSL_EMAIL}" \
    --agree-tos \
    --no-eff-email \
    -d "${DOMAIN}" \
    -d "www.${DOMAIN}" \
    -d "api.${DOMAIN}" \
    -d "crm.${DOMAIN}"

# ─── Step 6: Reload Nginx with real cert ───
echo "🔄 Reloading Nginx with real certificate..."
docker compose exec nginx nginx -s reload

echo ""
echo "═══════════════════════════════════════════════════"
echo "  ✅ SSL Setup Complete!"
echo ""
echo "  Your certificates are in: ./certbot/conf/"
echo "  Auto-renewal is handled by the certbot container"
echo ""
echo "  Next step: Run ./scripts/deploy.sh to start everything"
echo "═══════════════════════════════════════════════════"
