#!/bin/bash
# ═══════════════════════════════════════════════════════
#  Shotlin — Update Cloudflare IP Whitelist
#  Fetches latest Cloudflare IPs and updates nginx config
# ═══════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
OUTPUT_FILE="${PROJECT_DIR}/nginx/conf.d/cloudflare-ips.conf"

echo "Fetching latest Cloudflare IP ranges..."

# Fetch IPv4 and IPv6 ranges
IPV4=$(curl -s https://www.cloudflare.com/ips-v4)
IPV6=$(curl -s https://www.cloudflare.com/ips-v6)

if [ -z "${IPV4}" ]; then
    echo "❌ Failed to fetch Cloudflare IPs"
    exit 1
fi

# Generate config
cat > "${OUTPUT_FILE}" << EOF
# ═══════════════════════════════════════════════════════
#  Cloudflare IP Ranges — For real_ip restoration
#  Source: https://www.cloudflare.com/ips/
#  Last updated: $(date '+%Y-%m-%d %H:%M:%S %Z')
#  Auto-updated via: ./scripts/update-cloudflare-ips.sh
# ═══════════════════════════════════════════════════════

# Cloudflare IPv4 ranges
EOF

for ip in ${IPV4}; do
    echo "set_real_ip_from ${ip};" >> "${OUTPUT_FILE}"
done

echo "" >> "${OUTPUT_FILE}"
echo "# Cloudflare IPv6 ranges" >> "${OUTPUT_FILE}"

for ip in ${IPV6}; do
    echo "set_real_ip_from ${ip};" >> "${OUTPUT_FILE}"
done

echo ""
echo "✅ Updated: ${OUTPUT_FILE}"
echo "   IPv4 ranges: $(echo "${IPV4}" | wc -l | tr -d ' ')"
echo "   IPv6 ranges: $(echo "${IPV6}" | wc -l | tr -d ' ')"
echo ""
echo "Remember to reload Nginx: docker compose exec nginx nginx -s reload"
