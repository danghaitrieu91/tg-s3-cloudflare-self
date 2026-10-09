# Configuration Reference

**English** | [Tiếng Việt](configuration.vi.md)

Where a value is set depends on how you deploy (see [deployment.md](deployment.md)):

| Where | Used by | How |
|-------|---------|-----|
| **GitHub Secret** | Path A (GitHub Actions) | Fork → Settings → Secrets and variables → Actions → Secrets |
| **GitHub Variable** | Path A (GitHub Actions) | Same page → Variables |
| **`.env`** | Path B (`deploy.sh`, Docker) | `cp .env.example .env`; read by `deploy.sh` and `docker-compose.yml` |
| **`wrangler.toml`** | Both paths | `[vars]`, bindings, cron; committed in the repository |
| **`.dev.vars`** | Local development (`wrangler dev`) | Git-ignored file in the project root |

Worker **secrets** (`TG_BOT_TOKEN`, `DEFAULT_CHAT_ID`, `TG_ADMIN_IDS`, `WORKER_URL`, `SSE_MASTER_KEY`, `VPS_URL`, `VPS_SECRET`) are uploaded to Cloudflare by the workflow or by `deploy.sh`. They are never written to `wrangler.toml`.

## Worker settings

These are the fields of the `Env` interface in `src/types.ts` plus `WEB_UPLOAD_BUCKET`.

| Name | Required | Purpose | Path A | Path B |
|------|----------|---------|--------|--------|
| `TG_BOT_TOKEN` | Yes | Telegram bot token from @BotFather. Also used to derive the webhook secret | Secret | `.env` |
| `DEFAULT_CHAT_ID` | Yes | Supergroup chat ID (`-100…`) where files are stored. The bot must be an admin there | Secret | `.env` |
| `TG_ADMIN_IDS` | Yes (enforced by CI and `deploy.sh`) | Comma-separated Telegram user IDs allowed to use the bot **and** the Mini App API (initData / Bearer auth), e.g. `123456789,987654321`. If the Worker runs without it, **any** Telegram user can use the bot and any Telegram user who opens the Mini App is accepted | Secret | `.env` |
| `WORKER_URL` | Automatic | Public URL of the Worker. Used for share links sent by the bot and for CDN cache purging in the cron job. Do not set it yourself | Set by CI (`https://<CUSTOM_DOMAIN>` or the `*.workers.dev` URL) | Set by `deploy.sh` (`https://<CF_CUSTOM_DOMAIN>` or the `*.workers.dev` URL) |
| `SSE_MASTER_KEY` | No | Base64 32-byte key for SSE-S3 (server-managed encryption). Generate with `openssl rand -base64 32`. Without it, SSE-S3 requests are rejected. Keep it forever: objects encrypted with it cannot be read without it | Secret (optional) | Auto-generated into `.env` |
| `VPS_URL` | No | Public HTTPS URL of the VPS processor (files > 20 MB, media processing) | Secret (optional) | `.env`; set automatically when `deploy.sh` creates the tunnel |
| `VPS_SECRET` | No | Shared secret between the Worker and the processor (the processor reads it as `AUTH_SECRET`) | Secret (optional; must match the processor) | Auto-generated into `.env` |
| `S3_REGION` | Yes (has default) | Region reported by the S3 API | `wrangler.toml` `[vars]`, default `us-east-1` | same |
| `WEB_UPLOAD_BUCKET` | No (default `files`) | Bucket used by the public web upload page. `off` (any case) or empty disables the page and `POST /api/web-upload`. Any other value must be a valid bucket name (`^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$` after lower-casing), otherwise uploads fail with `500`. See [web-upload.md](web-upload.md) | Variable; unset = value in `wrangler.toml` (`files`) | `wrangler.toml` `[vars]` only — **`deploy.sh` ignores `WEB_UPLOAD_BUCKET` in `.env`** |
| `DB` | Yes (binding) | D1 database `tg-s3-self-db` (metadata) | `wrangler.toml` `[[d1_databases]]`; `database_id` filled by CI | same; `database_id` filled by `deploy.sh` |
| `CACHE` | No (binding) | R2 bucket `tg-s3-self-cache` (hot-file cache, files ≤ 20 MB) | `wrangler.toml` `[[r2_buckets]]`; bucket created by CI | same; created by `deploy.sh` with a 90-day lifecycle rule |

To find your Telegram user ID, send any message to [@userinfobot](https://t.me/userinfobot).

## GitHub Actions only

| Name | Kind | Required | Purpose |
|------|------|----------|---------|
| `CLOUDFLARE_API_TOKEN` | Secret | Yes | API token used by wrangler. Permissions: [deployment.md → Create a Cloudflare API token](deployment.md#3-create-a-cloudflare-api-token) |
| `CLOUDFLARE_ACCOUNT_ID` | Secret | Yes | Cloudflare account ID |
| `DEPLOY_ENABLED` | Variable | Yes | Must be exactly `true`; otherwise the deploy job is skipped |
| `CUSTOM_DOMAIN` | Variable | No | Bare hostname in a zone on the same Cloudflare account, e.g. `files.example.com` (no `https://`, no path). CI adds a Custom Domain route and sets `workers_dev = false` (CI workspace only). Use a dedicated, unused hostname: an existing DNS record or Custom Domain on it is re-pointed to this Worker ([deployment.md](deployment.md#custom-domain)) |
| `WEB_UPLOAD_BUCKET` | Variable | No | Overrides `wrangler.toml` at deploy time (`--var`). See [Worker settings](#worker-settings) |

## `deploy.sh` / `.env` only

| Name | Required | Purpose |
|------|----------|---------|
| `CLOUDFLARE_API_TOKEN` | Docker mode: yes; otherwise no | API token for wrangler. Without it (non-Docker modes) `wrangler login` is used. Same permissions as Path A, plus **Cloudflare Tunnel: Edit** and **DNS: Edit** for automatic tunnel creation |
| `CLOUDFLARE_ACCOUNT_ID` | No | Needed when the token can access several accounts. The legacy name `CF_ACCOUNT_ID` is still accepted |
| `CF_CUSTOM_DOMAIN` | No | Sets `WORKER_URL`/webhook to `https://<domain>` and, in Docker mode, creates the tunnel hostname `vps.<domain>`. It does **not** route the Worker: add `[[routes]]` and `workers_dev = false` to `wrangler.toml` yourself ([deployment.md](deployment.md#custom-domain-and-tunnel)) |
| `CF_TUNNEL_TOKEN` | No | Cloudflare Tunnel connector token. Written automatically when the tunnel is created; set it manually for a tunnel you created yourself (then also set `VPS_URL`) |
| `TELEGRAM_API_ID`, `TELEGRAM_API_HASH` | No | Enable the Local Bot API container (files up to 2 GB). Both are required. Get them at [my.telegram.org](https://my.telegram.org) → **API development tools** |
| `TG_LOCAL_API` | Automatic | Bot API endpoint used by the processor. Set to `http://telegram-bot-api:8081` when the Local Bot API is enabled, otherwise `https://api.telegram.org` |
| `D1_DATABASE_ID` | Automatic | D1 database ID remembered after the first deploy (the Docker deploy container cannot persist `wrangler.toml`) |
| `VPS_SECRET`, `SSE_MASTER_KEY` | Automatic | Generated on first run if empty, see [Worker settings](#worker-settings) |
| `VPS_SSH` | `--vps` only | SSH target for the processor server, e.g. `root@your-server` (key-based login required) |
| `VPS_DEPLOY_DIR` | No | Directory on the server for `--vps`, default `/opt/tg-s3-self` |
| `VPS_PORT` | No | Port used by the `--vps` health check (default `3000`). `docker-compose.yml` runs the processor on port 3000 |

**Getting `TELEGRAM_API_ID` and `TELEGRAM_API_HASH`:**

1. Go to [my.telegram.org](https://my.telegram.org) and log in with your phone number.
2. Click **API development tools**.
3. Create an application (the fields are metadata only): any **App title** (e.g. `tg-s3`), a 5–32 character alphanumeric **Short name**, **Platform** `Other`, leave URL and description empty.
4. Copy `api_id` (number) and `api_hash` (string) into `.env`.

## Local development

Create `.dev.vars` with at least `TG_BOT_TOKEN` and `DEFAULT_CHAT_ID` (optionally any other Worker setting above). `[vars]` from `wrangler.toml` apply as well. Run `X_LOCAL_EXPLORER=false npx wrangler dev`; see [deployment.md → Local development](deployment.md#local-development).

## wrangler.toml

```toml
name = "tg-s3-self"
main = "src/index.ts"
compatibility_date = "2026-03-15"
workers_dev = true

[vars]
S3_REGION = "us-east-1"
WEB_UPLOAD_BUCKET = "files"

[[d1_databases]]
binding = "DB"
database_name = "tg-s3-self-db"
# D1 ID below stays empty in git; CI / deploy.sh fill it in (keep the value line comment-free)
database_id = ""
migrations_dir = "migrations"

[[r2_buckets]]
binding = "CACHE"
bucket_name = "tg-s3-self-cache"

[triggers]
crons = ["0 */6 * * *"]
```

- Keep `database_id = ""` in the repository; CI fills it in its own workspace. Never put a comment on the `database_id` line: `deploy.sh` parses that line.
- There is no `[[routes]]` section by default. Path A adds one when `CUSTOM_DOMAIN` is set; for Path B add it yourself (see [deployment.md](deployment.md#custom-domain-and-tunnel)).
- The schema is managed by the SQL files in `migrations/` (`wrangler d1 migrations apply`).

### Cron maintenance tasks

The scheduled handler runs every 6 hours and:

1. Cleans expired share tokens.
2. Cleans orphaned share tokens (object deleted but share remains).
3. Cleans stale multipart uploads (> 24 hours).
4. Cleans orphaned chunks.
5. Cleans expired password attempt records.
6. Runs a consistency check (a sample of ~2% of objects, clamped to 5–50, verifying Telegram file access).
7. Cleans the R2 cache (evicts objects deleted from D1).
8. Applies bucket lifecycle rules (deletes expired objects).

## Security notes

- **S3 credentials** are stored in D1 and used for AWS SigV4 verification. Create, revoke and scope them per bucket in the Mini App **Keys** tab.
- **Webhook secret** is derived from `TG_BOT_TOKEN` (HMAC-SHA256 of `tg-s3-webhook`); there is no separate variable. Changing the bot token requires re-registering the webhook (re-deploy).
- **`TG_ADMIN_IDS`** limits who can control the bot and who can use the Mini App API. CI and `deploy.sh` refuse to deploy without it.
- **Web upload** is public and enabled by default; read [web-upload.md](web-upload.md).
- **`CLOUDFLARE_API_TOKEN`** can modify your Cloudflare account. Keep it in GitHub Secrets or `.env`, never in the repository. `.env` and `.dev.vars` are in `.gitignore`.

## Limits

| Resource | Limit |
|----------|-------|
| Web upload / Mini App upload | 20 MB per file |
| Telegram Bot API file transfer | 20 MB (public Bot API) / 2 GB (Local Bot API via the processor) |
| R2 cache | Files ≤ 20 MB are cached |

Cloudflare plan limits (requests, D1 queries, R2 operations) change over time; check Cloudflare's current documentation for Workers, D1 and R2 limits for your plan.
