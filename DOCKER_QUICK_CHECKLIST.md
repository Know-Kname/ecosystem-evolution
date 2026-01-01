# Docker Quick Checklist
## Unified Device & Homelab Manager

Fast-reference checklist for common Docker pitfalls. See `LLM_DOCKER_BUILD_REFERENCE.md` for detailed explanations.

**Target**: Windows 11 Pro + Docker Desktop (WSL2) + Ubiquiti Dream Machine homelab

---

## 🔴 CRITICAL (Will cause bugs if missed)

| Issue | Fix |
|-------|-----|
| Container ignores SIGTERM, won't stop gracefully | Add `tini` or `dumb-init` as entrypoint |
| Shell form CMD breaks signals | Use exec form: `CMD ["python", "app.py"]` not `CMD python app.py` |
| Volume files owned by root, host can't edit | Match UID/GID or use `user: "${UID}:${GID}"` in compose |
| Secrets visible in `docker history` | Use BuildKit `--mount=type=secret` or runtime secrets |
| Container fills disk with logs | Set `max-size` and `max-file` in logging options |
| Zombie processes accumulate | Use init system (tini) |
| Network tools (ping/nmap) fail | Add `cap_add: [NET_RAW, NET_ADMIN]` or `network_mode: host` |
| Windows volume mounts are slow | Use named volumes or store code in WSL2 filesystem |
| Docker Desktop eats all RAM | Set limits in `%USERPROFILE%\.wslconfig` |

---

## 🟡 IMPORTANT (Will cause issues in production)

| Issue | Fix |
|-------|-----|
| Running as root | Add `USER appuser` after creating user |
| No health checks | Add `HEALTHCHECK` that tests actual app functionality |
| Container restarts loop | Set `restart: unless-stopped` and fix underlying issue |
| depends_on doesn't wait for ready | Use `condition: service_healthy` |
| Timezone mismatch in logs | Mount `/etc/localtime:/etc/localtime:ro` |
| Build cache invalidated every time | Order Dockerfile: deps first, code last |
| Fat images (1GB+) | Use multi-stage builds, minimal base images |
| Using `:latest` tag | Pin specific versions |

---

## 🟢 BEST PRACTICES (Quality of life)

| Practice | Implementation |
|----------|----------------|
| Structured logging | Output JSON to stdout, not files |
| Graceful shutdown | Handle SIGTERM, cleanup, then exit |
| Multi-arch support | Build with `docker buildx` for amd64+arm64 |
| Dev hot-reload | Use compose profiles, mount source code |
| Secrets separation | Use `.env` files (gitignored) or Docker secrets |
| Resource limits | Set `mem_limit` and `cpus` in compose |

---

## 📋 Dockerfile Template (Python)

```dockerfile
# syntax=docker/dockerfile:1.4
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    tini curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m appuser
WORKDIR /app
COPY --from=builder /root/.local /home/appuser/.local
COPY --chown=appuser:appuser . .
ENV PATH=/home/appuser/.local/bin:$PATH PYTHONUNBUFFERED=1
USER appuser
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1
EXPOSE 8000
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["python", "main.py"]
```

## 📋 Dockerfile Template (Next.js 16)

```dockerfile
FROM node:22-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup -g 1001 -S nodejs && adduser -S nextjs -u 1001
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder /app/public ./public
USER nextjs
EXPOSE 3000
CMD ["node", "server.js"]
```
*Requires `output: 'standalone'` in next.config.ts*

---

## 📋 Compose Template

```yaml
# No 'version' field needed - Compose V2 uses latest spec automatically
services:
  app:
    build: .
    user: "${UID:-1000}:${GID:-1000}"
    volumes:
      - app-data:/app/data
      - ./config:/app/config:ro
    environment:
      - LOG_LEVEL=INFO
      - TZ=America/Detroit
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  network-agent:
    build: ./agent
    network_mode: host
    cap_add: [NET_RAW, NET_ADMIN]
    environment:
      - TZ=America/Detroit
    depends_on:
      app:
        condition: service_healthy
    deploy:
      resources:
        limits:
          memory: 256M

volumes:
  app-data:
```

---

## 🔧 Debug Commands

```bash
# Why did container exit?
docker inspect <container> --format='{{.State.ExitCode}} {{.State.Error}}'

# Secrets in image?
docker history --no-trunc <image> | grep -iE 'secret|password|key|token'

# Resource usage
docker stats

# Shell into container
docker exec -it <container> /bin/sh

# Follow logs with timestamps
docker logs -f --timestamps <container>
```

---

## ⚠️ Project-Specific Warnings

| Project | Watch Out For |
|---------|---------------|
| **network-doctor-pro** | Needs NET_RAW; Python 3.12+; target UDM at 192.168.0.1, not XB8 (bridge mode) |
| **personal-life-organizer** | Mount OneDrive via named volume; run as host user; persist hash DB |
| **ecosystem-evolution** | PowerShell scripts need `mcr.microsoft.com/powershell` or Windows containers |
| **eternavue-web** | Next.js 16 + Node 22; use `output: 'standalone'` in config; multi-stage build |

## 🌐 Network Quick Reference

| Network | Gateway | Subnet | Purpose |
|---------|---------|--------|---------|
| **plzdnt** | 192.168.0.1 (UDM) | 192.168.0.x | Primary homelab |
| **WhyFye** | 192.168.1.1 | 192.168.1.x | Secondary/DMP |
| **GL-A1300-5a7-5G** | 192.168.8.1 | 192.168.8.x | Travel router |

---

## 🪟 Windows Quick Fixes

```powershell
# Limit Docker Desktop RAM - create %USERPROFILE%\.wslconfig
@"
[wsl2]
memory=8GB
processors=4
"@ | Out-File -FilePath "$env:USERPROFILE\.wslconfig" -Encoding utf8

# Restart WSL to apply
wsl --shutdown
```

```powershell
# Fix CRLF issues in shell scripts
git config --global core.autocrlf input
```

---

*Print this. Tape it to your monitor. Check it every time.*

