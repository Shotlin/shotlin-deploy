#!/bin/bash
# ═══════════════════════════════════════════════════════
#  Shotlin — Cloudflare Origin Certificate Setup
#  Run ONCE to install your Cloudflare Origin SSL certificate
# ═══════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
cd "${PROJECT_DIR}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║   🔒 Cloudflare Origin Certificate Setup   ║"
echo "  ╚═══════════════════════════════════════════╝"
echo -e "${NC}"

# Create SSL directory
mkdir -p ssl

# Check if certs already exist
if [ -f "ssl/origin.pem" ] && [ -f "ssl/origin-key.pem" ]; then
    echo -e "${YELLOW}⚠️  SSL certificates already exist!${NC}"
    echo ""
    openssl x509 -in ssl/origin.pem -noout -subject -dates 2>/dev/null || true
    echo ""
    read -p "Overwrite existing certificates? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Keeping existing certificates."
        exit 0
    fi
fi

echo ""
echo -e "${CYAN}═══ How to get your Cloudflare Origin Certificate ═══${NC}"
echo ""
echo "  1. Login to Cloudflare Dashboard → your domain"
echo "  2. Go to: SSL/TLS → Origin Server"
echo "  3. Click 'Create Certificate'"
echo "  4. Settings:"
echo "     - Key type: RSA (2048)"
echo "     - Hostnames: *.shotlin.com, shotlin.com"
echo "     - Validity: 15 years"
echo "  5. Click 'Create'"
echo "  6. You'll see TWO text boxes:"
echo "     - 'Origin Certificate' (the cert)"
echo "     - 'Private Key' (the key)"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT: Copy the Private Key NOW — Cloudflare won't show it again!${NC}"
echo ""

# ─── Get Origin Certificate ───
echo -e "${GREEN}[1/2] Paste your Origin Certificate below${NC}"
echo "  (starts with -----BEGIN CERTIFICATE-----)"
echo "  (ends with -----END CERTIFICATE-----)"
echo "  Press Ctrl+D when done:"
echo ""
cat > ssl/origin.pem

echo ""

# ─── Get Private Key ───
echo -e "${GREEN}[2/2] Paste your Private Key below${NC}"
echo "  (starts with -----BEGIN PRIVATE KEY-----)"
echo "  (ends with -----END PRIVATE KEY-----)"
echo "  Press Ctrl+D when done:"
echo ""
cat > ssl/origin-key.pem

# ─── Set permissions ───
chmod 600 ssl/origin-key.pem
chmod 644 ssl/origin.pem

# ─── Validate ───
echo ""
echo -e "${CYAN}Validating certificate...${NC}"

if openssl x509 -in ssl/origin.pem -noout -subject -dates 2>/dev/null; then
    echo ""
    echo -e "${GREEN}✅ Certificate is valid!${NC}"
else
    echo -e "${RED}❌ Certificate validation failed! Check your paste.${NC}"
    exit 1
fi

if openssl rsa -in ssl/origin-key.pem -check -noout 2>/dev/null; then
    echo -e "${GREEN}✅ Private key is valid!${NC}"
else
    echo -e "${RED}❌ Private key validation failed! Check your paste.${NC}"
    exit 1
fi

# Verify cert and key match
CERT_MOD=$(openssl x509 -noout -modulus -in ssl/origin.pem 2>/dev/null | md5sum)
KEY_MOD=$(openssl rsa -noout -modulus -in ssl/origin-key.pem 2>/dev/null | md5sum)

if [ "$CERT_MOD" = "$KEY_MOD" ]; then
    echo -e "${GREEN}✅ Certificate and key match!${NC}"
else
    echo -e "${RED}❌ Certificate and key DO NOT match!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  🔒 SSL Setup Complete!${NC}"
echo ""
echo "  Certificate: ssl/origin.pem"
echo "  Private Key: ssl/origin-key.pem"
echo ""
echo -e "  ${CYAN}IMPORTANT — Set these in Cloudflare Dashboard:${NC}"
echo "  1. SSL/TLS → Overview → Set to 'Full (Strict)'"
echo "  2. SSL/TLS → Edge Certificates → Always Use HTTPS: ON"
echo "  3. SSL/TLS → Edge Certificates → Minimum TLS: TLS 1.2"
echo "  4. SSL/TLS → Edge Certificates → HSTS: Enable"
echo ""
echo "  Next step: ./scripts/deploy.sh"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
