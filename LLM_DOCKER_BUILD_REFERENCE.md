# LLM Docker Build Reference Sheet
## Unified Device & Homelab Manager

> **Purpose**: Critical, often-overlooked technical details for building containerized device/homelab management applications. Use this as context when generating Dockerfiles, compose files, and container orchestration code.

---

## 0. ENVIRONMENT CONTEXT

### Host Systems
- **OS**: Windows 11 Pro on all personal laptops and DMP office desktops
- **Primary Use**: Development workstations + homelab controller

### Network Topology
```
Internet (Xfinity)
    │
    ▼
┌─────────────────┐
│  XB8-T Gateway  │  (Bridge Mode - passes through to UDM)
│                 │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│  Ubiquiti Dream Machine (192.168.0.1)  - "plzdnt" network   │
│  Main router/firewall for homelab                           │
├─────────────────────────────────────────────────────────────┤
│  Devices:                                                    │
│  • 192.168.0.3   welcome-me (MSI PULSE, Win11 Pro)          │
│  • 192.168.0.5   kali-raspberrypi (Raspberry Pi, Linux)     │
│  • 192.168.0.79  iPhone14                                    │
│  • 192.168.0.143 GL-A1300 (travel router)                   │
│  • 192.168.0.154 DELL-94Z02 (Win11 Pro)                     │
│  • 192.168.0.186 serve (Zimaboard, Windows)                 │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│  Dream-Router (192.168.1.1) - "WhyFye" network              │
│  Secondary network (possibly DMP office or guest)           │
├─────────────────────────────────────────────────────────────┤
│  Devices:                                                    │
│  • 192.168.1.72  kali-raspberrypi                           │
│  • 192.168.1.134 Netgear Switch                             │
│  • 192.168.1.157 gl-a1300                                   │
│  • 192.168.1.225 SERVINGDMP                                 │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  GL-A1300 Slate Plus (192.168.8.1) - Travel router          │
│  "GL-A1300-5a7-5G" network - portable setup                 │
├─────────────────────────────────────────────────────────────┤
│  Devices:                                                    │
│  • 192.168.8.124 DELL-94Z02 (Win11 Pro)                     │
└─────────────────────────────────────────────────────────────┘
```

### Key Infrastructure
| Device | IP | Role |
|--------|-----|------|
| **Ubiquiti Dream Machine** | 192.168.0.1 | Primary router/firewall |
| **Dream-Router** | 192.168.1.1 | Secondary network |
| **GL-A1300 Slate Plus** | 192.168.8.1 | Travel router |
| **Zimaboard (serve)** | 192.168.0.186 | Home server |
| **kali-raspberrypi** | 192.168.0.5 | Security research / scanning |
| **XB8-T Gateway** | Bridge mode | ISP handoff only |

### Project Stack Versions
| Project | Runtime | Key Dependencies |
|---------|---------|------------------|
| **eternavue-web** | Node.js 22 LTS | Next.js 16, React 19, Tailwind v4 |
| **network-doctor-pro** | Python 3.12+ | scapy, nmap, rich, click |
| **ecosystem-evolution** | PowerShell 7+ / Bash | WSL2, Docker Desktop |
| **personal-life-organizer** | Python 3.12+ | Standard library |

### Windows 11 / Docker Desktop Considerations
- **Volume Performance**: Bind mounts from Windows filesystem to Linux containers are slow. Prefer named volumes or store code in WSL2 filesystem (`\\wsl$\Ubuntu\...`)
- **Line Endings**: Set `git config core.autocrlf input` to avoid CRLF issues in shell scripts
- **Path Translation**: Use forward slashes in compose files; Docker translates automatically
- **WSL2 Memory**: Docker Desktop can consume excessive RAM. Set limits in `%USERPROFILE%\.wslconfig`:
  ```ini
  [wsl2]
  memory=8GB
  processors=4
  ```

---

## 1. PROCESS MANAGEMENT (CRITICAL - OFTEN MISSED)

### The PID 1 Problem
Containers run your app as PID 1. Unlike normal processes, PID 1:
- Does NOT receive default signal handlers
- Must explicitly handle SIGTERM/SIGINT or containers won't stop gracefully
- Must reap zombie child processes or they accumulate

**ALWAYS use an init system:**

```dockerfile
# Option 1: Use tini (recommended - tiny, purpose-built)
RUN apk add --no-cache tini
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["python", "main.py"]

# Option 2: Use dumb-init
RUN apt-get install -y dumb-init
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["./app"]

# Option 3: Docker's built-in (add to docker run, not Dockerfile)
# docker run --init myimage
```

**Why this matters for homelab manager:**
- PowerShell/Bash scripts spawn child processes (ping, nmap, git)
- Without init, SIGTERM won't propagate → hung containers on restart
- Zombie processes accumulate during long diagnostic runs

### Shell Form vs Exec Form

```dockerfile
# BAD - Shell form (runs via /bin/sh -c, breaks signal handling)
CMD python main.py

# GOOD - Exec form (runs directly, signals work correctly)
CMD ["python", "main.py"]

# BAD - Can't expand variables in exec form directly
CMD ["echo", "$HOME"]

# GOOD - If you need shell expansion, be explicit
CMD ["/bin/sh", "-c", "echo $HOME"]
```

---

## 2. VOLUME PERMISSIONS (MOST COMMON PAIN POINT)

### The UID/GID Mismatch Problem
- Container user (e.g., UID 1000) writes files to mounted volume
- Host user (e.g., UID 501 on macOS) can't read/modify them
- Or vice versa: container can't write to host-owned directories

**Solutions:**

```dockerfile
# Solution 1: Match host UID at build time (simple but inflexible)
ARG UID=1000
ARG GID=1000
RUN groupadd -g $GID appgroup && \
    useradd -u $UID -g $GID -m appuser
USER appuser

# Build with: docker build --build-arg UID=$(id -u) --build-arg GID=$(id -g) .
```

```dockerfile
# Solution 2: Fix permissions at runtime (more flexible)
# In entrypoint script:
#!/bin/sh
# If running as root, fix ownership then drop privileges
if [ "$(id -u)" = "0" ]; then
    chown -R appuser:appgroup /app/data
    exec gosu appuser "$@"
fi
exec "$@"
```

```yaml
# Solution 3: Use user namespace remapping (Docker daemon config)
# /etc/docker/daemon.json
{
  "userns-remap": "default"
}
```

**For homelab manager specifically:**
```yaml
# docker-compose.yml
services:
  controller:
    volumes:
      - ./config:/app/config
      - ./data:/app/data
    # Run as current user on Linux
    user: "${UID:-1000}:${GID:-1000}"
```

### Named Volumes vs Bind Mounts

| Type | Use Case | Permissions |
|------|----------|-------------|
| **Named Volume** | Database, persistent app data | Docker manages, cleaner |
| **Bind Mount** | Config files, code in dev | Host controls permissions |
| **tmpfs** | Secrets, temp files | RAM only, never persisted |

```yaml
volumes:
  # Named volume - Docker manages
  db-data:
  
services:
  app:
    volumes:
      # Named volume
      - db-data:/var/lib/postgresql/data
      # Bind mount (use for configs you edit on host)
      - ./config:/app/config:ro  # :ro = read-only
      # tmpfs for secrets
      - type: tmpfs
        target: /app/secrets
        tmpfs:
          size: 1m
```

---

## 3. NETWORKING PATTERNS

### DNS Resolution Timing
**Problem**: Container A tries to connect to Container B before B is ready.

```yaml
services:
  controller:
    depends_on:
      db:
        condition: service_healthy  # Wait for health check, not just start
      
  db:
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres"]
      interval: 5s
      timeout: 5s
      retries: 5
```

### Network Modes for Device Access

```yaml
services:
  # Standard bridge - isolated, port mapping required
  web:
    networks:
      - frontend
    ports:
      - "8080:80"

  # Host network - direct access to host network stack
  # Required for: network scanning, ICMP (ping), raw sockets
  network-doctor:
    network_mode: host
    cap_add:
      - NET_RAW      # Required for ping/scapy
      - NET_ADMIN    # Required for interface configuration

  # macvlan - container gets its own IP on physical network
  # Useful for: appearing as separate device to router/switches
  iot-scanner:
    networks:
      macvlan_net:
        ipv4_address: 192.168.1.50

networks:
  macvlan_net:
    driver: macvlan
    driver_opts:
      parent: eth0
    ipam:
      config:
        - subnet: 192.168.1.0/24
          gateway: 192.168.1.1
```

### Container-to-Container Communication

```yaml
# Use service names, not IPs
services:
  api:
    environment:
      - DATABASE_URL=postgresql://db:5432/mydb  # 'db' resolves via Docker DNS
      
  db:
    # No ports exposed to host - only accessible within Docker network
    expose:
      - "5432"
```

---

## 4. MULTI-ARCHITECTURE BUILDS

**Critical for homelab**: Your fleet likely includes x86_64 (desktops), ARM64 (Raspberry Pi 4/5), ARMv7 (older Pis).

```dockerfile
# Dockerfile that works across architectures
FROM --platform=$BUILDPLATFORM python:3.12-slim AS builder

# Install build dependencies
RUN pip install --user -r requirements.txt

FROM python:3.12-slim
COPY --from=builder /root/.local /root/.local
```

```bash
# Build for multiple platforms
docker buildx create --name multiarch --use
docker buildx build \
  --platform linux/amd64,linux/arm64,linux/arm/v7 \
  --tag myregistry/homelab-manager:latest \
  --push .
```

```yaml
# docker-compose.yml - let Docker pick the right image
services:
  agent:
    image: myregistry/homelab-manager:latest
    # Docker automatically pulls correct arch
```

---

## 5. SECRETS MANAGEMENT

### What NOT to Do

```dockerfile
# NEVER - Secrets baked into image layer (visible in docker history)
ENV API_KEY=super_secret_key
COPY .env /app/.env
RUN echo "password123" > /app/secret.txt
```

### Proper Approaches

```yaml
# Method 1: Docker Secrets (Swarm mode or Compose v3.1+)
services:
  app:
    secrets:
      - db_password
      - api_key
    environment:
      - DB_PASSWORD_FILE=/run/secrets/db_password

secrets:
  db_password:
    file: ./secrets/db_password.txt  # Not committed to git
  api_key:
    external: true  # Created via: docker secret create api_key ./key.txt
```

```yaml
# Method 2: Environment file (simpler, less secure)
services:
  app:
    env_file:
      - .env  # Add to .gitignore!
```

```dockerfile
# Method 3: Build-time secrets (Docker BuildKit)
# syntax=docker/dockerfile:1.4
FROM python:3.12-slim

# Secret available only during this RUN, not persisted in layer
RUN --mount=type=secret,id=github_token \
    GITHUB_TOKEN=$(cat /run/secrets/github_token) && \
    pip install git+https://${GITHUB_TOKEN}@github.com/private/repo.git
```

```bash
# Build with secret
DOCKER_BUILDKIT=1 docker build \
  --secret id=github_token,src=./github_token.txt \
  -t myimage .
```

---

## 6. HEALTH CHECKS

### Why Default Health Checks Fail

```dockerfile
# BAD - Just checks if process is running
HEALTHCHECK CMD pgrep python

# BETTER - Checks if app is actually responding
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# BEST - Dedicated health endpoint that checks dependencies
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD python /app/healthcheck.py || exit 1
```

```python
# healthcheck.py - Comprehensive health check
#!/usr/bin/env python3
import sys
import psutil
import requests

def check_health():
    # Check 1: Memory usage under threshold
    if psutil.virtual_memory().percent > 90:
        return False, "Memory usage too high"
    
    # Check 2: Can reach database
    try:
        requests.get("http://db:5432", timeout=5)
    except:
        return False, "Database unreachable"
    
    # Check 3: Disk space
    if psutil.disk_usage('/').percent > 95:
        return False, "Disk nearly full"
    
    return True, "Healthy"

if __name__ == "__main__":
    healthy, msg = check_health()
    print(msg)
    sys.exit(0 if healthy else 1)
```

---

## 7. LOGGING BEST PRACTICES

### Structured Logging for Container Environments

```python
# Use JSON logging - parseable by log aggregators
import logging
import json
from datetime import datetime

class JSONFormatter(logging.Formatter):
    def format(self, record):
        return json.dumps({
            "timestamp": datetime.utcnow().isoformat(),
            "level": record.levelname,
            "message": record.getMessage(),
            "module": record.module,
            "function": record.funcName,
            "line": record.lineno
        })

# Configure root logger
handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logging.root.addHandler(handler)
logging.root.setLevel(logging.INFO)
```

### Log Driver Configuration

```yaml
services:
  app:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"      # Prevent disk fill
        max-file: "3"        # Keep 3 rotated files
        compress: "true"
        labels: "service,environment"
```

### Stream stdout/stderr Correctly

```dockerfile
# Force Python to not buffer output
ENV PYTHONUNBUFFERED=1

# Or in code
import sys
sys.stdout.reconfigure(line_buffering=True)
```

---

## 8. GRACEFUL SHUTDOWN

### Handling SIGTERM Properly

```python
import signal
import sys
import time

class GracefulShutdown:
    def __init__(self):
        self.shutdown_requested = False
        signal.signal(signal.SIGTERM, self._handle_sigterm)
        signal.signal(signal.SIGINT, self._handle_sigterm)
    
    def _handle_sigterm(self, signum, frame):
        print("Shutdown signal received, finishing current work...")
        self.shutdown_requested = True
    
    def should_continue(self):
        return not self.shutdown_requested

# Usage
shutdown = GracefulShutdown()
while shutdown.should_continue():
    do_work()
    time.sleep(1)

# Cleanup
print("Cleaning up...")
save_state()
close_connections()
sys.exit(0)
```

### Compose Stop Timeouts

```yaml
services:
  diagnostics:
    stop_grace_period: 30s  # Give 30s for graceful shutdown before SIGKILL
    stop_signal: SIGTERM    # Default, but be explicit
```

---

## 9. DOCKERFILE PATTERNS FOR THIS PROJECT

### Controller Service (FastAPI + SQLite)

```dockerfile
# syntax=docker/dockerfile:1.4
FROM python:3.12-slim AS builder

WORKDIR /app
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

FROM python:3.12-slim

# Install tini for proper signal handling
RUN apt-get update && apt-get install -y --no-install-recommends \
    tini curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd --create-home --shell /bin/bash appuser
WORKDIR /app

# Copy dependencies from builder
COPY --from=builder /root/.local /home/appuser/.local
ENV PATH=/home/appuser/.local/bin:$PATH

# Copy application
COPY --chown=appuser:appuser . .

USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

EXPOSE 8000

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Network Diagnostics Agent

```dockerfile
FROM python:3.12-slim

# Network tools require specific packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    tini \
    iputils-ping \
    iproute2 \
    net-tools \
    nmap \
    tcpdump \
    curl \
    dnsutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# This container needs elevated privileges for network operations
# Will be granted via docker-compose cap_add, not in Dockerfile

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["python", "main.py", "--mode", "standard"]
```

### PowerShell Manager (Windows Container)

```dockerfile
# For Windows-native operations
FROM mcr.microsoft.com/powershell:latest

SHELL ["pwsh", "-Command"]

WORKDIR /app

# Copy scripts and config
COPY Device-Ecosystem-Manager-v3.2.ps1 .
COPY canonical-config/ ./canonical-config/

# Set execution policy
RUN Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process

ENTRYPOINT ["pwsh", "-File", "Device-Ecosystem-Manager-v3.2.ps1"]
CMD ["-Mode", "HealthCheck"]
```

### Next.js 16 App (eternavue-web)

```dockerfile
# syntax=docker/dockerfile:1.4
FROM node:22-alpine AS base

# Install dependencies only when needed
FROM base AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app

# Install dependencies based on the preferred package manager
COPY package.json package-lock.json* ./
RUN npm ci --legacy-peer-deps

# Rebuild the source code only when needed
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Next.js collects anonymous telemetry - disable it
ENV NEXT_TELEMETRY_DISABLED=1

# Build with standalone output for smaller production image
RUN npm run build

# Production image, copy only necessary files
FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copy built assets
COPY --from=builder /app/public ./public

# Leverage output file tracing to reduce image size
# https://nextjs.org/docs/advanced-features/output-file-tracing
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000

ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

# Note: Don't use tini here - Node.js handles signals properly
CMD ["node", "server.js"]
```

**Required next.config.ts change for standalone:**
```typescript
// next.config.ts
const nextConfig = {
  output: 'standalone',  // Required for optimized Docker builds
  // ... other config
};
export default nextConfig;
```

---

## 10. COMPOSE PATTERNS

### Full Stack with Proper Depends/Health

```yaml
# NOTE: 'version' field is obsolete in Compose V2+ (current default)
# Omit it entirely - Docker uses the latest Compose Specification

services:
  controller:
    build:
      context: ./controller
      dockerfile: Dockerfile
    ports:
      - "8000:8000"
    volumes:
      - controller-data:/app/data
      - ./config:/app/config:ro
    environment:
      - DATABASE_URL=sqlite:///app/data/homelab.db
      - LOG_LEVEL=INFO
    depends_on:
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped
    # Resource limits (critical for homelab stability)
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 128M
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  agent:
    build:
      context: ./agent
      dockerfile: Dockerfile
    network_mode: host  # Required for network scanning
    cap_add:
      - NET_RAW
      - NET_ADMIN
    volumes:
      - ./reports:/app/reports
      - /etc/localtime:/etc/localtime:ro  # Sync timezone (Linux)
      # Windows alternative: mount nothing, set TZ env var instead
    environment:
      - CONTROLLER_URL=http://localhost:8000
      - SCAN_INTERVAL=300
      - TZ=America/Detroit  # Set timezone explicitly for Windows hosts
    depends_on:
      controller:
        condition: service_healthy
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M

  redis:
    image: redis:7-alpine
    volumes:
      - redis-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 128M

  # Development hot-reload
  dev:
    profiles: ["dev"]  # Only starts with: docker compose --profile dev up
    build:
      context: ./controller
      target: builder
    volumes:
      - ./controller:/app
    command: uvicorn main:app --host 0.0.0.0 --port 8000 --reload
    ports:
      - "8000:8000"

volumes:
  controller-data:
  redis-data:
```

### Override Files for Environments

```yaml
# docker-compose.override.yml (automatically loaded in dev)
services:
  controller:
    build:
      target: builder  # Use dev stage
    volumes:
      - ./controller:/app  # Hot reload
    environment:
      - DEBUG=true
      - LOG_LEVEL=DEBUG

# docker-compose.prod.yml (use with -f flag)
services:
  controller:
    image: ghcr.io/myorg/homelab-controller:${VERSION:-latest}
    environment:
      - DEBUG=false
      - LOG_LEVEL=WARNING
```

---

## 11. CI/CD INTEGRATION

### GitHub Actions Workflow

```yaml
name: Build and Push

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: ${{ github.event_name != 'pull_request' }}
          tags: |
            ghcr.io/${{ github.repository }}:latest
            ghcr.io/${{ github.repository }}:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Scan for vulnerabilities
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ghcr.io/${{ github.repository }}:${{ github.sha }}
          format: 'sarif'
          output: 'trivy-results.sarif'

      - name: Upload scan results
        uses: github/codeql-action/upload-sarif@v2
        with:
          sarif_file: 'trivy-results.sarif'
```

---

## 12. COMMON GOTCHAS CHECKLIST

Before finalizing any Docker configuration, verify:

- [ ] **Init process**: Using tini/dumb-init or --init flag?
- [ ] **Signal handling**: ENTRYPOINT uses exec form, not shell form?
- [ ] **Non-root user**: Container runs as non-root user?
- [ ] **Volume permissions**: UID/GID matches between container and host?
- [ ] **Health checks**: All services have meaningful health checks?
- [ ] **Resource limits**: Memory and CPU limits set?
- [ ] **Logging**: Logs go to stdout/stderr, not files inside container?
- [ ] **Secrets**: No secrets in image layers or environment variables in Dockerfile?
- [ ] **Timezone**: /etc/localtime mounted if time-sensitive?
- [ ] **Graceful shutdown**: Application handles SIGTERM?
- [ ] **Dependencies**: Using depends_on with condition: service_healthy?
- [ ] **Restart policy**: Set to unless-stopped or always?
- [ ] **Build cache**: Dockerfile ordered for optimal caching?
- [ ] **Multi-arch**: Building for all target architectures?
- [ ] **Version pinning**: Base images use specific tags, not :latest?

---

## 13. DEBUGGING COMMANDS

```bash
# View container logs with timestamps
docker logs -f --timestamps container_name

# Execute shell in running container
docker exec -it container_name /bin/sh

# View container resource usage
docker stats container_name

# Inspect container config
docker inspect container_name

# View network details
docker network inspect bridge

# Check why container exited
docker inspect container_name --format='{{.State.ExitCode}}'
docker inspect container_name --format='{{.State.Error}}'

# View image layers and sizes
docker history image_name

# Check for secrets leaked in image
docker history --no-trunc image_name | grep -i secret

# Clean up everything
docker system prune -a --volumes

# View real-time events
docker events
```

---

## 14. PROJECT-SPECIFIC NOTES

### For ecosystem-evolution

- PowerShell manager needs Windows containers OR PowerShell Core on Linux
- WSL setup script runs natively in WSL, not containerized
- Canonical config should be mounted read-only from git repo
- Drift detection needs write access to generate reports
- **XB8-T Gateway**: In bridge mode - not the management target

### For network-doctor-pro

- Requires NET_RAW capability for ping/scapy
- Consider host network mode for full network access
- Reports should persist via named volume
- May need to run privileged for some scans (avoid if possible)
- **Python 3.12+** required (pyproject.toml specifies >=3.9 but 3.12 recommended)
- **scapy** needs libpcap - install in Dockerfile
- **✅ Default gateway**: `192.168.0.1` (Ubiquiti Dream Machine)
- **Primary targets**:
  - Ubiquiti Dream Machine: 192.168.0.1 (plzdnt network)
  - Dream-Router: 192.168.1.1 (WhyFye network)
  - Zimaboard server: 192.168.0.186
  - kali-raspberrypi: 192.168.0.5 (can run scans from here too)

### For personal-life-organizer

- Needs read access to cloud sync folders (OneDrive, iCloud, etc.)
- **Windows paths**: OneDrive typically at `C:\Users\<user>\OneDrive`
- Write access to target organization directory
- Consider running as current user for permission compatibility
- Hash database should persist between runs (SQLite recommended)

### For eternavue-web

- **Next.js 16 + React 19** - use `output: 'standalone'` in next.config.ts
- Use Node.js 22 LTS (current) not 20
- Multi-stage build with standalone output (see Dockerfile pattern above)
- **Tailwind v4** - PostCSS config may differ from v3
- Static assets can be served from CDN
- Environment variables for API endpoints at runtime via `NEXT_PUBLIC_*`

---

## 15. HOMELAB MANAGEMENT TOOLS

Consider these tools for managing your containerized homelab:

| Tool | Purpose | Docker Support |
|------|---------|----------------|
| **Portainer** | Web UI for Docker management | Native container |
| **Traefik** | Reverse proxy with auto-SSL | Container with Docker socket |
| **Tailscale** | Zero-config VPN (WireGuard) | Sidecar or host install |
| **Watchtower** | Automatic container updates | Container watching socket |
| **Duplicati** | Encrypted volume backups | Container with volume access |
| **Prometheus + Grafana** | Metrics and dashboards | Container stack |
| **Loki** | Log aggregation | Container with Docker driver |

### Recommended Stack for This Project

```yaml
services:
  # Your apps...
  
  portainer:
    image: portainer/portainer-ce:latest
    ports:
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - portainer-data:/data
    restart: unless-stopped

  traefik:
    image: traefik:v3.0
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik:/etc/traefik
    restart: unless-stopped

volumes:
  portainer-data:
```

---

## 16. WINDOWS-SPECIFIC PATTERNS

### Volume Mounts from Windows

```yaml
services:
  app:
    volumes:
      # Windows path - works but slow
      - C:/Users/chugh/OneDrive:/data/onedrive:ro
      
      # Better: Use WSL2 filesystem path
      - /mnt/c/Users/chugh/OneDrive:/data/onedrive:ro
      
      # Best: Named volume (Docker manages, fastest)
      - app-data:/app/data
```

### Docker Desktop Resource Limits

Create `%USERPROFILE%\.wslconfig`:
```ini
[wsl2]
memory=8GB
processors=4
swap=2GB
localhostForwarding=true
```

### PowerShell Helpers for Docker

```powershell
# Quick container logs
function dlog { docker logs -f $args }

# Quick shell into container
function dsh { docker exec -it $args /bin/sh }

# Clean up stopped containers and unused images
function dprune { docker system prune -f }

# Restart compose stack
function drestart { docker compose down; docker compose up -d }
```

---

*Last updated: December 2024*
*Target Environment: Windows 11 Pro + Docker Desktop (WSL2) + Ubiquiti Dream Machine homelab*
*Networks: plzdnt (192.168.0.x), WhyFye (192.168.1.x), GL-A1300 travel (192.168.8.x)*
*Use this document as context when generating Docker configurations for the Unified Device & Homelab Manager project.*

