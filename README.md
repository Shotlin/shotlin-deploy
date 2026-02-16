# 🚀 Shotlin Deployment

Production-grade Docker deployment for the full Shotlin platform — **frontend**, **dashboard (CRM)**, **backend API**, and **PostgreSQL** — behind an **Nginx** reverse proxy with **automatic SSL certificates**.

---

## 📁 Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     INTERNET                            │
└──────────────┬──────────────────────────┬───────────────┘
               │ :80 (→ :443)            │ :443
┌──────────────▼──────────────────────────▼───────────────┐
│                  Nginx Reverse Proxy                     │
│   ┌─────────────┬──────────────┬──────────────────┐     │
│   │ shotlin.com  │ api.shotlin │ crm.shotlin.com  │     │
│   └──────┬──────┘──────┬──────┘──────┬───────────┘     │
└──────────┼─────────────┼─────────────┼──────────────────┘
           │             │             │
   ┌───────▼─────┐ ┌─────▼──────┐ ┌───▼──────────┐
   │  Frontend   │ │  Backend   │ │  Dashboard   │
   │  Next.js    │ │  Fastify   │ │  Next.js     │
   │  :3000      │ │  :4000     │ │  :3001       │
   └─────────────┘ └─────┬──────┘ └──────────────┘
                         │
                   ┌─────▼──────┐
                   │ PostgreSQL │
                   │  :5432     │
                   └────────────┘
```

---

## 🔒 Security Features

| Feature | Status |
|---------|--------|
| **SSL/TLS** (Let's Encrypt) | ✅ Auto-renewing |
| **HTTP → HTTPS** redirect | ✅ |
| **Rate Limiting** (API: 30/s, Login: 5/min) | ✅ |
| **Security Headers** (HSTS, CSP, XSS, etc.) | ✅ |
| **Non-root containers** | ✅ |
| **Internal-only database** | ✅ Not exposed to host |
| **Nginx server tokens** hidden | ✅ |
| **A+ SSL Labs rating** ciphers | ✅ |
| **Automated daily backups** | ✅ 7d/4w/3m retention |
| **Health checks** on all services | ✅ |

---

## ⚡ Quick Start — 5 Minutes to Production

### Prerequisites
- A VPS/server with **Docker** and **Docker Compose** installed
- A domain with DNS pointing to your server:
  - `shotlin.com` → your server IP
  - `www.shotlin.com` → your server IP
  - `api.shotlin.com` → your server IP
  - `crm.shotlin.com` → your server IP

### Step 1: Clone repos side by side
```bash
cd /opt  # or wherever you prefer
git clone <your-repo> shotlin_backend
git clone <your-repo> shotlin_dashboard
git clone <your-repo> shotlin_frontend_next_js
git clone <your-repo> shotlin-deploy
```

Your directory should look like:
```
/opt/
├── shotlin_backend/
├── shotlin_dashboard/
├── shotlin_frontend_next_js/
└── shotlin-deploy/          ← You are here
```

### Step 2: Configure environment
```bash
cd shotlin-deploy
cp .env.example .env
nano .env   # Fill in ALL values
```

⚠️ **Critical**: Generate secure secrets:
```bash
# Generate JWT secret
openssl rand -hex 32

# Generate PostgreSQL password
openssl rand -base64 24
```

### Step 3: Set up SSL certificates
```bash
chmod +x scripts/*.sh
./scripts/init-ssl.sh
```

### Step 4: Deploy everything! 🚀
```bash
./scripts/deploy.sh
```

That's it! Your platform is live at:
- 🌐 **Frontend**: `https://shotlin.com`
- 📊 **Dashboard**: `https://crm.shotlin.com`
- 🔌 **API**: `https://api.shotlin.com`

### Step 5: Seed the admin user
```bash
./scripts/manage.sh seed-admin
```

---

## 🛠 Management Commands

```bash
# ─── Status & Monitoring ───
./scripts/manage.sh status       # Service health + resource usage
./scripts/manage.sh logs         # Follow ALL logs
./scripts/manage.sh logs-api     # Backend logs only
./scripts/manage.sh logs-web     # Frontend logs only
./scripts/manage.sh logs-crm     # Dashboard logs only

# ─── Database ───
./scripts/manage.sh backup       # Create immediate backup
./scripts/manage.sh restore <file>  # Restore from backup
./scripts/manage.sh shell-db     # PostgreSQL interactive shell
./scripts/manage.sh migrate      # Run pending migrations
./scripts/manage.sh seed-admin   # Create/reset admin user

# ─── SSL ───
./scripts/manage.sh ssl-status   # Check certificate expiry
./scripts/manage.sh ssl-renew    # Force renewal

# ─── Deployment ───
./scripts/deploy.sh              # Deploy (cached build)
./scripts/deploy.sh --build      # Force rebuild all images
./scripts/deploy.sh --restart    # Restart without rebuild
./scripts/manage.sh update       # Pull latest + redeploy

# ─── Maintenance ───
./scripts/manage.sh stop         # Stop all services
./scripts/manage.sh down         # Stop + remove containers
./scripts/manage.sh disk         # Show disk usage
./scripts/manage.sh clean        # Remove unused Docker resources
```

---

## 🔄 Updating Your Code

After pushing new code to any of the three repos:

```bash
cd shotlin-deploy

# Pull latest code in each repo
cd ../shotlin_backend && git pull
cd ../shotlin_dashboard && git pull
cd ../shotlin_frontend_next_js && git pull

# Rebuild and redeploy
cd ../shotlin-deploy
./scripts/deploy.sh --build
```

---

## 💾 Backup & Recovery

### Automated Backups
- **Schedule**: Daily at 2:00 AM
- **Retention**: 7 daily + 4 weekly + 3 monthly
- **Location**: `./backups/`

### Manual Backup
```bash
./scripts/manage.sh backup
```

### Restore
```bash
./scripts/manage.sh restore backups/manual_20260216.sql.gz
```

---

## 🏗 File Structure

```
shotlin-deploy/
├── docker-compose.yml          # Master orchestration
├── .env.example                # Template for secrets
├── .env                        # Your secrets (git-ignored)
├── .gitignore
├── README.md
├── nginx/
│   ├── nginx.conf              # Main Nginx config
│   └── conf.d/
│       ├── default.conf        # Virtual hosts (3 domains)
│       ├── ssl-params.conf     # TLS hardening
│       ├── security-headers.conf  # OWASP headers
│       └── proxy-params.conf   # Shared proxy settings
├── scripts/
│   ├── deploy.sh               # One-command deploy
│   ├── init-ssl.sh             # First-time SSL setup
│   ├── manage.sh               # Management CLI
│   └── backup.sh               # Automated backup service
├── certbot/                    # SSL certs (git-ignored)
│   ├── conf/
│   └── www/
└── backups/                    # DB backups (git-ignored)
```

---

## ⚙️ Customization

### Change Domain
1. Edit `DOMAIN` in `.env`
2. Update DNS records
3. Run `./scripts/init-ssl.sh` for new certs
4. Run `./scripts/deploy.sh --build`

### Adjust Rate Limits
Edit `nginx/conf.d/default.conf` — look for `limit_req_zone` and `limit_req` directives.

### Scale Services
```bash
docker compose up -d --scale backend=3
```

---

## 🚨 Troubleshooting

| Issue | Fix |
|-------|-----|
| SSL cert expired | `./scripts/manage.sh ssl-renew` |
| Backend won't start | `./scripts/manage.sh logs-api` |
| Database connection error | `./scripts/manage.sh status` — check postgres health |
| Out of disk space | `./scripts/manage.sh clean` then `./scripts/manage.sh disk` |
| Need to reset admin password | `./scripts/manage.sh seed-admin` |
| Container keeps restarting | `docker compose logs <service> --tail=50` |
