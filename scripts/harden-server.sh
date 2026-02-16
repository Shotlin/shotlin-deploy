#!/bin/bash
# ═══════════════════════════════════════════════════════
#  Shotlin — AWS EC2 Server Hardening Script
#  Run ONCE after connecting to a fresh EC2 instance
#  This script makes your server production-secure
# ═══════════════════════════════════════════════════════

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
info() { echo -e "${CYAN}[→]${NC} $*"; }

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║     🛡  SERVER HARDENING SCRIPT            ║"
echo "  ╚═══════════════════════════════════════════╝"
echo -e "${NC}"

# Must be root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}This script must be run as root (use sudo)${NC}"
    exit 1
fi

# ─── 1. System Updates ───
info "Updating system packages..."
apt update && apt upgrade -y
log "System updated"

# ─── 2. Install Essential Security Tools ───
info "Installing security tools..."
apt install -y \
    fail2ban \
    unattended-upgrades \
    apt-listchanges \
    ufw \
    logrotate \
    htop \
    curl \
    gnupg \
    ca-certificates
log "Security tools installed"

# ─── 3. Create Deploy User ───
if ! id "deploy" &>/dev/null; then
    info "Creating deploy user..."
    adduser --disabled-password --gecos "" deploy
    usermod -aG sudo deploy
    echo "deploy ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/deploy
    chmod 440 /etc/sudoers.d/deploy
    
    # Copy SSH keys from root to deploy user
    if [ -d /root/.ssh ]; then
        mkdir -p /home/deploy/.ssh
        cp /root/.ssh/authorized_keys /home/deploy/.ssh/ 2>/dev/null || true
        chown -R deploy:deploy /home/deploy/.ssh
        chmod 700 /home/deploy/.ssh
        chmod 600 /home/deploy/.ssh/authorized_keys 2>/dev/null || true
    fi
    log "Deploy user created"
else
    log "Deploy user already exists"
fi

# ─── 4. SSH Hardening ───
info "Hardening SSH..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

cat > /etc/ssh/sshd_config.d/shotlin-hardened.conf << 'EOF'
# Shotlin SSH Hardening
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
MaxAuthTries 3
MaxSessions 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
Protocol 2
EOF

systemctl restart ssh
log "SSH hardened (root login disabled, key-only auth)"

# ─── 5. Firewall Setup ───
info "Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
echo "y" | ufw enable
log "Firewall enabled (22, 80, 443 only)"

# ─── 6. Fail2Ban Configuration ───
info "Configuring Fail2Ban..."

cat > /etc/fail2ban/jail.d/shotlin.conf << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = 22
maxretry = 3
bantime = 86400
findtime = 600

[nginx-http-auth]
enabled = true
port = 80,443
maxretry = 3
bantime = 3600

[nginx-botsearch]
enabled = true
port = 80,443
maxretry = 2
bantime = 86400

[nginx-limit-req]
enabled = true
port = 80,443
maxretry = 10
bantime = 3600
logpath = /var/log/nginx/error.log
EOF

systemctl enable fail2ban
systemctl restart fail2ban
log "Fail2Ban configured (SSH: 3 attempts → 24h ban)"

# ─── 7. Kernel Hardening (sysctl) ───
info "Applying kernel security parameters..."

cat > /etc/sysctl.d/99-shotlin-security.conf << 'EOF'
# ─── Network Security ───
# Prevent IP spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Disable ICMP redirects (prevent MITM)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0

# Enable SYN cookies (prevent SYN flood)
net.ipv4.tcp_syncookies = 1

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Log suspicious packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore ICMP broadcast
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Disable IPv6 if not needed
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1

# ─── Memory / Performance ───
# Optimize for low memory
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.overcommit_memory = 0

# ─── File Security ───
# Restrict core dumps
fs.suid_dumpable = 0

# Restrict dmesg
kernel.dmesg_restrict = 1

# Restrict kernel pointer leaks
kernel.kptr_restrict = 2
EOF

sysctl --system > /dev/null 2>&1
log "Kernel hardened"

# ─── 8. Set Up Swap (Critical for 2GB RAM) ───
if [ ! -f /swapfile ]; then
    info "Creating 1GB swap file..."
    fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log "Swap file created (1GB)"
else
    log "Swap already exists"
fi

# ─── 9. Auto Security Updates ───
info "Enabling automatic security updates..."

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

systemctl enable unattended-upgrades
log "Auto security updates enabled"

# ─── 10. Docker Log Rotation ───
info "Configuring Docker log rotation..."

mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "5m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "live-restore": true,
    "userns-remap": "default",
    "no-new-privileges": true
}
EOF

# Restart Docker if it's running
systemctl restart docker 2>/dev/null || true
log "Docker log rotation configured"

# ─── 11. Disable Unused Services ───
info "Disabling unused services..."
systemctl disable --now snapd.service 2>/dev/null || true
systemctl disable --now snapd.socket 2>/dev/null || true
systemctl disable --now ModemManager.service 2>/dev/null || true
log "Unused services disabled"

# ─── 12. Set File Permissions ───
info "Securing file permissions..."
chmod 700 /root
chmod 600 /etc/ssh/sshd_config
log "File permissions secured"

# ─── Summary ───
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  🛡  Server Hardening Complete!${NC}"
echo ""
echo "  ✅ System updated"
echo "  ✅ Deploy user created (key-only SSH)"
echo "  ✅ Root login disabled"
echo "  ✅ Firewall: 22, 80, 443 only"
echo "  ✅ Fail2Ban: SSH brute force protection"
echo "  ✅ Kernel hardened (SYN cookies, IP spoof protection)"
echo "  ✅ 1GB swap file (for 2GB RAM)"
echo "  ✅ Auto security updates"
echo "  ✅ Docker log rotation"
echo ""
echo -e "  ${YELLOW}⚠️  IMPORTANT: Log in with deploy user from now on:${NC}"
echo "     ssh deploy@YOUR_SERVER_IP"
echo ""
echo "  Next steps:"
echo "  1. Install Docker: see deployment guide"
echo "  2. Clone repos: see deployment guide"
echo "  3. Deploy: ./scripts/deploy.sh"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
