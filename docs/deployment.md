# Deployment Guide

**English** | [Tiếng Việt](deployment.vi.md)

There are two ways to deploy `tg-s3-cloudflare-self`:

| Path | How | Best for |
|------|-----|----------|
| **A. GitHub Actions** (recommended) | Fork the repo, add Secrets/Variables, run the workflow | Worker only, files up to 20 MB, no local tooling |
| **B. `deploy.sh`** | Run the script on your machine or a server (with or without Docker) | Adding the VPS processor (files up to 2 GB, media processing) |

Both paths deploy the same Cloudflare resources:

| Resource | Name |
|----------|------|
| Worker | `tg-s3-self` |
| D1 database | `tg-s3-self-db` |
| R2 bucket (cache) | `tg-s3-self-cache` |

All configuration options are listed in [configuration.md](configuration.md). The public web upload page is **enabled by default** — read [web-upload.md](web-upload.md) before you deploy.

## Prerequisites

1. **Telegram bot** — create one with [@BotFather](https://t.me/BotFather) (`/newbot`) and keep the token.
2. **Telegram supergroup** — create a group, add your bot as an **administrator**, and get its chat ID (a negative number starting with `-100`, for example `-1001234567890`). One way: add [@userinfobot](https://t.me/userinfobot) to the group temporarily, or send a message in the group and open `https://api.telegram.org/bot<TOKEN>/getUpdates` and look for `chat.id`.
3. **Your Telegram user ID** — send any message to [@userinfobot](https://t.me/userinfobot). It goes into `TG_ADMIN_IDS` (required).
4. **Cloudflare account** with **R2 activated** — R2 needs a subscription even for the free usage tier: dashboard → **Storage & databases → R2 → Overview** → complete the checkout flow. Source: [R2 get started](https://developers.cloudflare.com/r2/get-started/).
5. Path B / local development only: **Node.js 22.18+** (the project uses wrangler v4; `npm test` needs Node's built-in TypeScript type stripping).

## Path A: GitHub Actions

The workflow is `.github/workflows/deploy.yml`. It runs on every push to `main` and on manual runs, but the deploy job is **skipped** until you set the repository Variable `DEPLOY_ENABLED` to `true`. A separate `test` job (type check and unit tests, no secrets) runs first on every push and on every pull request, also in forks; the deploy job only starts after it passes and never runs for pull requests.

> [!NOTE]
> The workflow has not been run end-to-end by the template authors; your fork's first run is the real test. If a step fails, see [Troubleshooting (Path A)](#troubleshooting-path-a).

### 1. Fork the repository

Fork `tg-s3-cloudflare-self` to your GitHub account (**Fork** button on the repository page). Optionally clone your fork if you want to edit locally:

```bash
git clone https://github.com/<your-github-user>/tg-s3-cloudflare-self.git
cd tg-s3-cloudflare-self
```

### 2. Register a workers.dev subdomain (one-time)

If you deploy **without** a custom domain, your Cloudflare account needs a `workers.dev` subdomain; otherwise `wrangler deploy` fails with *"You need to register a workers.dev subdomain before publishing to workers.dev"*.

In the Cloudflare dashboard go to **Workers & Pages** and set **Your subdomain** (workers.dev URLs have the form `<worker-name>.<your-subdomain>.workers.dev`). Source: [workers.dev](https://developers.cloudflare.com/workers/configuration/routing/workers-dev/).

Your Worker URL will then be `https://tg-s3-self.<your-subdomain>.workers.dev`.

### 3. Create a Cloudflare API token

In the Cloudflare dashboard open **My Profile → API Tokens** (or **Manage Account → API Tokens** for an account token) → **Create Token**. Source: [Create API token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/).

Use **Create Custom Token** (or start from the **Edit Cloudflare Workers** template — it does **not** include D1, so add it; template contents: [API token templates](https://developers.cloudflare.com/fundamentals/api/reference/template/)) and make sure the token has:

| Scope | Permission | Level |
|-------|-----------|-------|
| Account | Workers Scripts | Edit |
| Account | D1 | Edit |
| Account | Workers R2 Storage | Edit |
| Account | Account Settings | Read |
| Zone *(only with `CUSTOM_DOMAIN`)* | DNS | Edit |
| Zone *(only with `CUSTOM_DOMAIN`)* | Workers Routes | Edit |

Restrict **Account Resources** to the account you deploy to, and (if used) **Zone Resources** to the zone of your custom domain. The token secret is shown only once.

Your **Account ID**: dashboard → **Workers & Pages** → **Account Details** → copy **Account ID**. Source: [Find account and zone IDs](https://developers.cloudflare.com/fundamentals/account/find-account-and-zone-ids/).

### 4. Add repository Secrets

In your fork: **Settings → Secrets and variables → Actions → Secrets → New repository secret**.

| Secret | Required | Value |
|--------|----------|-------|
| `CLOUDFLARE_API_TOKEN` | Yes | Token from step 3 |
| `CLOUDFLARE_ACCOUNT_ID` | Yes | Your Cloudflare account ID |
| `TG_BOT_TOKEN` | Yes | Bot token from @BotFather |
| `DEFAULT_CHAT_ID` | Yes | Supergroup chat ID, e.g. `-1001234567890` (bot must be admin) |
| `TG_ADMIN_IDS` | Yes | Comma-separated Telegram user IDs allowed to use the bot and the Mini App, e.g. `123456789,987654321` |
| `SSE_MASTER_KEY` | No | Base64 32-byte key for SSE-S3 encryption (`openssl rand -base64 32`). Without it SSE-S3 is unavailable. Never change it once objects are encrypted. |
| `VPS_URL` | No | Public URL of a VPS processor (see Path B) |
| `VPS_SECRET` | No | Shared secret with that processor |

### 5. Add repository Variables

Same page, **Variables** tab → **New repository variable**.

| Variable | Required | Value |
|----------|----------|-------|
| `DEPLOY_ENABLED` | Yes | `true` — otherwise the job is skipped |
| `CUSTOM_DOMAIN` | No | e.g. `files.example.com` — a bare hostname (no `https://`, no path) in a zone on the **same** Cloudflare account. When set, CI routes the Worker there and disables the `*.workers.dev` URL. Use a dedicated, unused hostname (see [Custom domain](#custom-domain)) |
| `WEB_UPLOAD_BUCKET` | No | Unset = `files` (web upload **ON**). `off` disables it. Any other value = bucket name (must be a valid bucket name). See [web-upload.md](web-upload.md) |

### 6. Enable Actions and run the first deploy

1. Open the **Actions** tab of your fork. GitHub disables workflows in forks until you confirm — click **I understand my workflows, go ahead and enable them**.
2. Select **Deploy to Cloudflare Workers** → **Run workflow** (branch `main`). Later pushes to `main` deploy automatically.
3. When the run is green, open the log of **Resolve Worker URL** to see your Worker URL.
4. Send `/start` to your bot **in a private chat** (the bot does not answer in groups). The bot command menu is not registered automatically; set it with @BotFather `/setcommands` if you want it — see [bot-commands.md](bot-commands.md).
5. Open the Mini App (`/miniapp` command or `https://<worker-url>/miniapp`) → **Keys** tab to create S3 credentials.

### What the workflow does

| Step | What happens |
|------|--------------|
| Test (job `test`) | `npm ci`, `npm run typecheck`, `npm test`. Runs on pushes and pull requests without any secret; a failure stops the deploy |
| Validate required secrets | Fails with `Missing required repository secret: <NAME>` if any of `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `TG_BOT_TOKEN`, `DEFAULT_CHAT_ID`, `TG_ADMIN_IDS` is empty, and with `Variable CUSTOM_DOMAIN must be a bare hostname …` if `CUSTOM_DOMAIN` is not a plain hostname |
| Ensure D1 database | Looks up `tg-s3-self-db` (`wrangler d1 list --json`), creates it if missing, and writes its ID into `wrangler.toml` **in the CI workspace only** (never committed). Fails with `wrangler d1 list failed …` if the lookup itself fails |
| Ensure R2 cache bucket | Creates `tg-s3-self-cache`; "already exists" is treated as success |
| Configure custom domain | Only if `CUSTOM_DOMAIN` is set: appends `[[routes]] pattern = "<domain>" custom_domain = true` and sets `workers_dev = false` (workspace only) |
| D1 bookmark | Prints `D1 bookmark before migrations: <id>` as a notice in the run summary: a D1 Time Travel restore point taken before the migrations (see [Backups and restore](#backups-and-restore)). Only a warning on a brand-new database |
| Apply D1 migrations | `wrangler d1 migrations apply tg-s3-self-db --remote` |
| Deploy Worker | `wrangler deploy --secrets-file …`: secrets are uploaded together with the code. Adds `--var WEB_UPLOAD_BUCKET:<value>` only if the Variable is set. Prints a notice saying whether web upload is ON or OFF |
| Resolve Worker URL | `https://<CUSTOM_DOMAIN>`, or the `*.workers.dev` URL parsed from the deploy output, which is then stored as the `WORKER_URL` secret |
| Register Telegram webhook | Calls `setWebhook` with `<WORKER_URL>/bot/webhook` and a secret token derived from the bot token (HMAC-SHA256). Fails the job if Telegram does not answer `ok` |
| Smoke test | Requests `<WORKER_URL>/tgs3-smoke-nonexistent/x` without credentials (up to 12 tries, 10 s apart) and expects `403` with the Worker's S3 error body `<Code>AccessDenied</Code>`, which proves that the new version reads D1 and runs the S3 auth path. A `403` from the edge (WAF, Access) does not count. Any other result fails the job |

### Custom domain

1. The domain must be an active zone in the **same** Cloudflare account ([Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)).
2. Add Zone permissions (DNS: Edit, Workers Routes: Edit) for that zone to the API token.
3. Set the Variable `CUSTOM_DOMAIN` (e.g. `files.example.com`) and re-run the workflow. Cloudflare creates the DNS record and certificate for the Custom Domain ([Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)).

> [!WARNING]
> **Use a dedicated, unused hostname.** In CI (non-interactive) wrangler deploys with override flags, so it does not ask before taking over the hostname: an existing DNS record, or another Worker's Custom Domain on that hostname, is silently re-pointed to this Worker. Never set `CUSTOM_DOMAIN` to a hostname that already serves something (your website, another app or Worker).

CI also sets `workers_dev = false`, so the `*.workers.dev` URL stops serving the Worker on that deploy ([workers.dev](https://developers.cloudflare.com/workers/configuration/routing/workers-dev/)). This matters for web upload protection: Cloudflare WAF rules and the Access setup in [web-upload.md](web-upload.md) apply to your custom domain, not to `*.workers.dev`.

### Re-deploys and updates

- Every push to `main` re-deploys. You can also re-run the workflow from the **Actions** tab (for example after changing a Secret or Variable — they only take effect on the next run).
- To pull template updates into your fork, use **Sync fork** on GitHub.
- D1 migrations are applied on every run; already-applied migrations are skipped.
- Keep `database_id = ""` committed in `wrangler.toml`; CI fills it in its workspace.
- Removing an optional Secret (for example `VPS_URL` or `SSE_MASTER_KEY`) from GitHub does **not** remove it from the Worker: deploys keep the secrets already stored there. Delete it from the Worker as well with `npx wrangler secret delete <NAME> --name tg-s3-self`.
- Pull requests (including from forks) only run the `test` job; nothing is deployed until the change lands on `main`.

### Troubleshooting (Path A)

| Symptom / message | Cause and fix |
|-------------------|---------------|
| Job shown as **skipped** | Variable `DEPLOY_ENABLED` is missing or not exactly `true` (it is a **Variable**, not a Secret) |
| `Missing required repository secret: <NAME>` | Add that Secret (step 4). Secret names are case-sensitive |
| `Variable CUSTOM_DOMAIN must be a bare hostname like files.example.com (no https://, no path)` | Set `CUSTOM_DOMAIN` to the hostname only, e.g. `files.example.com` — no scheme, no path, no trailing slash |
| `You need to register a workers.dev subdomain before publishing to workers.dev` | One-time: dashboard → **Workers & Pages** → set **Your subdomain** (step 2). Not needed if you use `CUSTOM_DOMAIN` |
| `Authentication error [code: 10000]` or other permission errors from wrangler | The API token is missing a permission from step 3, is scoped to another account/zone, or `CLOUDFLARE_ACCOUNT_ID` belongs to a different account |
| `wrangler d1 list failed (check CLOUDFLARE_ACCOUNT_ID and that the API token has D1: Edit)` | `CLOUDFLARE_ACCOUNT_ID` is wrong, or the token lacks **D1: Edit** / is scoped to another account. The wrangler output is printed above the error |
| `Could not find or create D1 database tg-s3-self-db` | Listing worked, but `wrangler d1 create` failed or the new database did not show up. The wrangler output is printed above the error |
| `Could not create R2 bucket tg-s3-self-cache` | Token lacks **Workers R2 Storage: Edit**, or R2 has not been activated on the account (see [Prerequisites](#prerequisites)). The wrangler output is printed above the error |
| `Could not find the workers.dev URL in the deploy output` | The deploy did not publish to `workers.dev` (usually no workers.dev subdomain registered). Register one, or set `CUSTOM_DOMAIN` |
| `setWebhook failed: <description>` | Telegram rejected the webhook; the `description` says why. Check that `TG_BOT_TOKEN` is correct and that the Worker URL is reachable over HTTPS (a new custom domain can take a few minutes — re-run the workflow) |
| `Could not reach api.telegram.org` | Network error from the runner; re-run the job |
| Custom domain errors during deploy | The zone is not on the same account, or the token lacks the Zone permissions |
| Bot does not answer | Talk to it in a **private** chat; check that your user ID is in `TG_ADMIN_IDS`; check `getWebhookInfo` (see [Verify the deployment](#verify-the-deployment)) |
| `Smoke test failed (HTTP <code>, expected 403 AccessDenied from the Worker)` | The new version is **already live** but does not answer correctly. `403-unexpected` means a 403 without the Worker's `AccessDenied` body: a WAF rule or Cloudflare Access is blocking the path, so allow it for S3 paths. `500` usually means a D1 or migration problem; `000`, `404` or `52x` usually means the URL is not serving yet (a new custom domain can take a few minutes — re-run the workflow). Check `npx wrangler tail tg-s3-self`, then fix and push, or roll the code back with `npx wrangler rollback --name tg-s3-self`. If a migration damaged data, restore D1 to the bookmark printed by the same run ([Backups and restore](#backups-and-restore)) |
| D1 backup: `getMe failed: … (TG_BOT_TOKEN invalid or revoked?)` | The backup itself already ran (this check runs after the upload, even if an earlier step failed), but Telegram rejects the bot token, so the bot is dead and cannot send alerts either. Get a new token from @BotFather if it was revoked, update the `TG_BOT_TOKEN` Secret, re-run **Deploy to Cloudflare Workers** (it uploads the token and re-registers the webhook), then re-run **D1 backup** |
| D1 backup: `No Telegram webhook is set; …` | The backup itself already ran, but the bot is not receiving messages. The next cron run (every 6 hours) re-registers the webhook if `WORKER_URL` is set; to fix it now, re-run **Deploy to Cloudflare Workers** |
| D1 backup: `D1 database tg-s3-self-db not found; not creating it` | The backup job never creates the database, so it cannot back up an empty replacement over good dumps. Check that `CLOUDFLARE_ACCOUNT_ID` is the right account. If the database is really gone, follow [Restore after the database is gone](#restore-after-the-database-is-gone) |
| D1 backup: `Could not read d1/last-count.json from tg-s3-self-backup; refusing to run without the shrink guard` | Reading the previous counts failed for a reason other than "the key does not exist" (network, permissions). The job stops instead of running without the guard. Check that the token has **Workers R2 Storage: Edit**, then re-run **D1 backup** |
| D1 backup: `refusing to overwrite backups: objects N -> M` | The number of objects in the verified dump dropped to 0 or below half of the last good backup. Nothing was uploaded; the existing backups are untouched. If this is unexpected, investigate and restore ([Backups and restore](#backups-and-restore)). If you deleted the files on purpose, accept the new count as described in [Daily backup](#daily-backup-github-actions) |

## Path B: `deploy.sh`

`deploy.sh` reads `.env`, creates/looks up the D1 database and R2 bucket, applies migrations, uploads secrets, deploys the Worker and registers the Telegram webhook. Depending on how it is started it also builds and runs the VPS processor in Docker.

### 1. Get the code and create `.env`

```bash
git clone https://github.com/<your-github-user>/tg-s3-cloudflare-self.git
cd tg-s3-cloudflare-self
cp .env.example .env
```

Edit `.env`. Required:

```bash
TG_BOT_TOKEN=123456:ABC-DEF...
DEFAULT_CHAT_ID=-1001234567890
TG_ADMIN_IDS=123456789
```

Recommended / mode-dependent:

```bash
CLOUDFLARE_API_TOKEN=...          # required in Docker mode; otherwise `wrangler login` is used
CLOUDFLARE_ACCOUNT_ID=...         # needed if the token can see several accounts
CF_CUSTOM_DOMAIN=files.example.com  # optional, see "Custom domain and tunnel" below
TELEGRAM_API_ID=...               # optional, Local Bot API (2 GB files)
TELEGRAM_API_HASH=...
```

If `TG_BOT_TOKEN`, `DEFAULT_CHAT_ID` or `TG_ADMIN_IDS` is missing and you run the script in an interactive terminal, it asks for them and saves the answers to `.env`. `VPS_SECRET` and `SSE_MASTER_KEY` are generated automatically and written to `.env` — back up `.env`, because objects encrypted with SSE-S3 cannot be read without the same `SSE_MASTER_KEY`.

All variables are described in [configuration.md](configuration.md).

### 2. Choose a mode

The script picks its mode automatically:

| Command | Condition | What it does |
|---------|-----------|--------------|
| `./deploy.sh` | Docker and `docker compose` available | **Host + Docker**: requires `CLOUDFLARE_API_TOKEN`; builds the `deploy` and `processor` images; deploys the Worker from the `deploy` container (and creates a Cloudflare Tunnel if configured); starts `processor` (+ `tunnel`, + `telegram-bot-api` when enabled) |
| `./deploy.sh` | No Docker | **Host without Docker**: deploys the Worker only, with the local wrangler (`npm install` if needed; `wrangler login` opens a browser if no `CLOUDFLARE_API_TOKEN`). No processor, no tunnel |
| `./deploy.sh --vps` | — | Deploys the Worker with the local wrangler, then deploys the processor to a remote server over SSH (`VPS_SSH`, e.g. `root@your-server`): installs Docker there if missing, copies `processor/` and `docker-compose.yml` with `rsync` into `VPS_DEPLOY_DIR` (default `/opt/tg-s3-self`), writes a `.env` there and runs `docker compose up -d` |

In every mode the Worker part does:

1. Find or create D1 `tg-s3-self-db` (ID taken from `wrangler.toml`, then `D1_DATABASE_ID` in `.env`, then the account; saved back as `D1_DATABASE_ID` in `.env`).
2. Create R2 `tg-s3-self-cache` and a 90-day lifecycle rule on it.
3. Apply D1 migrations (`--remote`).
4. Upload secrets: `TG_BOT_TOKEN`, `DEFAULT_CHAT_ID`, `VPS_SECRET`, plus `VPS_URL`, `SSE_MASTER_KEY`, `TG_ADMIN_IDS` when set.
5. `wrangler deploy`.
6. Set the `WORKER_URL` secret to `https://<CF_CUSTOM_DOMAIN>` if set, otherwise to the `*.workers.dev` URL from the deploy output.
7. Register the Telegram webhook at `<WORKER_URL>/bot/webhook` (a failure is printed as a warning, not an error).

> [!NOTE]
> In host-without-Docker and `--vps` modes the script writes the D1 ID into your local `wrangler.toml`. If you also deploy with GitHub Actions, do not commit that change — keep `database_id = ""` in the repository.

Secrets that you later remove from `.env` (for example `VPS_URL`) stay on the Worker; delete them with `npx wrangler secret delete <NAME> --name tg-s3-self`.

### Web upload with `deploy.sh`

`deploy.sh` does **not** pass `WEB_UPLOAD_BUCKET` from `.env`. To change the bucket or disable web upload, edit `wrangler.toml` before running the script:

```toml
[vars]
WEB_UPLOAD_BUCKET = "off"   # or another bucket name; default "files" = ON
```

See [web-upload.md](web-upload.md).

### Custom domain and tunnel

`CF_CUSTOM_DOMAIN` is used for two things only:

- `WORKER_URL` and the webhook URL become `https://<CF_CUSTOM_DOMAIN>`.
- In Docker mode, a Cloudflare Tunnel named `tg-s3-self` is created with the hostname `vps.<CF_CUSTOM_DOMAIN>` → `http://processor:3000`, a proxied DNS CNAME is created (if the zone is found in your account), and `CF_TUNNEL_TOKEN` and `VPS_URL=https://vps.<CF_CUSTOM_DOMAIN>` are written to `.env`. The token then also needs **Account → Cloudflare Tunnel: Edit** and **Zone → DNS: Edit**.

`deploy.sh` does **not** attach the domain to the Worker. Before running it with `CF_CUSTOM_DOMAIN`, add the route yourself and close the `*.workers.dev` URL in `wrangler.toml` ([Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/), [workers.dev](https://developers.cloudflare.com/workers/configuration/routing/workers-dev/)):

```toml
workers_dev = false

[[routes]]
pattern = "files.example.com"
custom_domain = true
```

The API token then also needs **Zone → Workers Routes: Edit** and **Zone → DNS: Edit** on that zone. Without the route, the webhook points to a hostname that does not serve the Worker; `deploy.sh` prints a warning when `CF_CUSTOM_DOMAIN` is set but `wrangler.toml` has no matching `pattern = "<CF_CUSTOM_DOMAIN>"` route. As in Path A, use a dedicated hostname that does not already serve something else.

Manual tunnel (without `CF_CUSTOM_DOMAIN`): in the Cloudflare dashboard go to **Networking → Tunnels → Create a tunnel**, then on the tunnel's **Routes** tab add a **Published application** with a hostname on one of your zones pointing to `http://processor:3000` ([Create a tunnel (dashboard)](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel/)). Set both `CF_TUNNEL_TOKEN` (the connector token) and `VPS_URL=https://<that-hostname>` in `.env` and run `./deploy.sh` again. When `CF_TUNNEL_TOKEN` is already set the script skips tunnel creation and does not change `VPS_URL`.

### Large files (up to 2 GB) with Local Bot API

The public Bot API limits files to 20 MB. For up to 2 GB you need **both**:

1. `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` in `.env` (from [my.telegram.org](https://my.telegram.org) → **API development tools** → create an application). The script then starts the `telegram-bot-api` container and points the processor at it (`TG_LOCAL_API`).
2. A processor that the Worker can reach: `VPS_URL` set to a public HTTPS URL of the processor (automatic with `CF_CUSTOM_DOMAIN` + tunnel in Docker mode, or `CF_TUNNEL_TOKEN` + `VPS_URL` set manually).

If only one of the two API values is set, the script warns and keeps the 20 MB limit.

> [!NOTE]
> `docker-compose.yml` does not publish the processor port on the host; it is reached through the tunnel container. In `--vps` mode the remote `.env` contains no `CF_TUNNEL_TOKEN` and the tunnel service is not started, so you must expose the processor yourself (reverse proxy or your own tunnel) and set `VPS_URL` accordingly.

### Updating

```bash
git pull
./deploy.sh          # or ./deploy.sh --vps
```

The third-party images (`aiogram/telegram-bot-api`, `cloudflare/cloudflared`) are not pinned to a version and are pulled only once: `deploy.sh` never pulls them again, so re-running it does not upgrade them. Upgrade deliberately, in the directory with `docker-compose.yml` (on the server for `--vps`), and check the logs afterwards:

```bash
docker compose pull && docker compose up -d
```

These services sit behind Compose profiles, so add the profiles you run to both commands, e.g. `docker compose --profile tunnel --profile localapi pull && docker compose --profile tunnel --profile localapi up -d`.

Useful Docker commands: `docker compose --profile tunnel logs -f`, `docker compose --profile tunnel restart`, `docker compose --profile tunnel down`.

### Troubleshooting (Path B)

| Symptom | Fix |
|---------|-----|
| Script exits because `.env` is missing | `cp .env.example .env` and fill it in |
| Required value missing (`TG_BOT_TOKEN`, `DEFAULT_CHAT_ID`, `TG_ADMIN_IDS`) | Fill it in `.env`, or run `./deploy.sh` in an interactive terminal to be prompted |
| Docker mode exits asking for `CLOUDFLARE_API_TOKEN` | Docker mode cannot use `wrangler login`; add the token to `.env` |
| Could not get the D1 database ID | Token lacks **D1: Edit**, or set `D1_DATABASE_ID` in `.env` to an existing database's ID |
| Webhook registration warning, or warning `CF_CUSTOM_DOMAIN=… has no [[routes]] entry in wrangler.toml` | Check the printed Telegram response; with `CF_CUSTOM_DOMAIN`, add a `[[routes]]` entry with `pattern = "<CF_CUSTOM_DOMAIN>"` and `custom_domain = true` to `wrangler.toml` ([Custom domain and tunnel](#custom-domain-and-tunnel)) and run again |
| Tunnel not created / processor "not reachable from outside" | Set `CF_CUSTOM_DOMAIN`, add **Cloudflare Tunnel: Edit** and **DNS: Edit** to the token, run again; or set `CF_TUNNEL_TOKEN` + `VPS_URL` manually |
| Processor problems | `docker compose logs processor` (on the server for `--vps`: `ssh <VPS_SSH> 'cd /opt/tg-s3-self && docker compose logs'`) |
| SSH failures in `--vps` mode | Key-based SSH must work non-interactively: `ssh -o BatchMode=yes <VPS_SSH> echo ok` |

## Alerts

The Worker's cron job (every 6 hours, both paths) sends a Telegram message titled **tg-s3 cron** to every user in `TG_ADMIN_IDS` when something needs attention. Each admin must send `/start` to the bot once, otherwise Telegram refuses to deliver the message. The cron job never deletes objects because of a Telegram error. Details of each step: [configuration.md → Cron maintenance tasks](configuration.md#cron-maintenance-tasks).

| Alert | Meaning and what to do |
|-------|------------------------|
| `getFile 400 for N of M sampled (lost, or not readable by this bot). Nothing was deleted.` + up to 10 keys | Telegram no longer serves these files (for example the messages were deleted from the storage group). Check the group; delete the listed objects yourself (bot `/delete`, Mini App or S3) if they are really gone |
| `All probes returned 400: TG_BOT_TOKEN is valid but probably belongs to a different bot …` | File IDs only work with the bot that uploaded them. `TG_BOT_TOKEN` was probably replaced by the token of another bot: put the original bot's token back and re-deploy |
| `getFile returned 401 … TG_BOT_TOKEN invalid or revoked.` | Create a new token for the same bot in @BotFather, update the Secret (or `.env`) and re-deploy |
| `Telegram unreachable or degraded: …` | At least half of the checks failed temporarily. Usually resolves by itself; act only if it repeats |
| `Webhook was missing → re-registered.` | Information only: the webhook was empty and the cron job set it again |
| `Webhook re-register FAILED …`, `Webhook: getWebhookInfo failed …` | Telegram refused or did not answer. Re-run the deploy (Path A workflow or `./deploy.sh`) |
| `Webhook points to another host (…); not changed.` | Another deployment (or a manual `setWebhook`) took over the bot. The cron job does not take it back; re-deploy this one if it should own the bot |
| `Webhook error: …` | Telegram reported a delivery error in the last 6 hours. Check that the Worker URL works, then [Verify the deployment](#verify-the-deployment) |
| `WORKER_URL not set: webhook self-heal disabled.` | Re-deploy so that CI or `deploy.sh` sets `WORKER_URL` |

If there were alerts but none could be delivered (no admin has started the bot, or the token is revoked), the cron run ends with the error `cron alerts undelivered`, visible in the Cloudflare dashboard under the Worker's **Cron Events**. A revoked token cannot send any Telegram message, so with GitHub Actions the [daily backup job](#daily-backup-github-actions) is the fallback: after the backup it checks the token with `getMe` and fails, which triggers GitHub's workflow failure email. Keep GitHub notification emails turned on.

## Backups and restore

Two layers protect the D1 metadata (the files themselves stay in Telegram, but without D1 they cannot be found):

| Layer | What | Where |
|-------|------|-------|
| D1 Time Travel | Point-in-time restore, built into D1, for as long as the database exists (retention: 7 days on Workers Free, 30 days on Workers Paid) | Cloudflare |
| Daily export (Path A only) | `.github/workflows/backup.yml`: one full SQL snapshot per day | R2 bucket `tg-s3-self-backup` |

`deploy.sh` (Path B) has no scheduled backup; Time Travel still applies.

### Time Travel (first choice)

Use it when the database still exists but its content is wrong (bad migration, mistaken mass delete). Every deploy run prints a restore point taken before migrations: open the run summary of **Deploy to Cloudflare Workers** and look for the notice `D1 bookmark before migrations: <id>`.

```bash
export CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ACCOUNT_ID=...
# restore to the bookmark printed by a deploy run
npx wrangler d1 time-travel restore tg-s3-self-db --bookmark=<id>
# or find a bookmark for a point in time, then restore it
npx wrangler d1 time-travel info tg-s3-self-db --timestamp=2026-10-09T12:00:00Z
```

A restore replaces the whole database in place; wrangler prints a bookmark of the state before the restore, so it can be undone the same way. See [D1 Time Travel](https://developers.cloudflare.com/d1/reference/time-travel/).

### Daily backup (GitHub Actions)

- Runs daily at 03:17 UTC and on demand (**Actions → D1 backup → Run workflow**), only when `DEPLOY_ENABLED` is `true`. The job times out after 20 minutes.
- It looks up `tg-s3-self-db` read-only and **never creates it**: if the database is missing the job fails with `D1 database tg-s3-self-db not found; not creating it`.
- It exports the whole database in one `wrangler d1 export` (schema and data of every table, including `d1_migrations`, so new tables are included automatically), then **verifies** the dump by restoring it into a scratch local D1 on the runner. The counts stored in `d1/last-count.json` come from that restore.
- It refuses to overwrite good backups (`refusing to overwrite backups: objects N -> M`) when the restored object count dropped to 0 or below 50% of the last good run. The very first run (no `d1/last-count.json` yet) accepts any count. Only a missing key counts as a first run: any other error reading the counts file stops the job (`Could not read d1/last-count.json …`).
- It uploads `d1/<Mon..Sun>.sql` (7-day rolling) and `d1/monthly/<YYYY-MM>.sql`, then `d1/last-count.json` (layout: [configuration.md → Backup workflow](configuration.md#backup-workflow)).
- After the upload it checks the bot with `getMe` and checks that a webhook is set. This check runs even when an earlier step failed, and a broken bot does not stop the backup, but it still fails the job, so GitHub sends its failure email even when Telegram cannot deliver messages.
- **S3 credentials are not backed up** (the `credentials` table is created by the dump, but its rows are removed). After a restore, create new keys in the Mini App **Keys** tab.
- On failure or cancellation every admin in `TG_ADMIN_IDS` also gets the Telegram message `tg-s3 daily D1 backup / bot health check failed: <run URL>` (best effort).
- **Accepting a deliberate large deletion**: delete the counts file, then run the workflow manually; that run is treated as a first run.

  ```bash
  npx wrangler r2 object delete tg-s3-self-backup/d1/last-count.json --remote
  ```

- GitHub pauses scheduled workflows in a repository with no activity for 60 days. Re-enable **D1 backup** in the **Actions** tab (or push a commit) if that happens; Time Travel keeps working meanwhile.

### Restore after the database is gone

Use this only when the database was deleted or Time Travel no longer reaches back far enough. A snapshot must be restored into an **empty** database.

1. Set the GitHub Variable `WEB_UPLOAD_BUCKET` to `off`, so the public page stays off until you have checked the result, and **do not push to `main` or run the deploy workflow** until step 6: on a missing database it creates a new one and applies every migration, so it is no longer empty.
2. Create an empty database and note its ID:

   ```bash
   export CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ACCOUNT_ID=...
   npx wrangler d1 create tg-s3-self-db
   ```

   Put the new ID into `database_id` in your local `wrangler.toml` for the next commands (do not commit it).
3. Download a snapshot from before the problem, for example Monday's:

   ```bash
   npx wrangler r2 object get tg-s3-self-backup/d1/Mon.sql --remote --file backup.sql
   ```

4. Load it, then apply only the migrations that are newer than the snapshot:

   ```bash
   npx wrangler d1 execute tg-s3-self-db --remote --file backup.sql
   npx wrangler d1 migrations apply tg-s3-self-db --remote
   ```

5. Check the counts, then delete the local file (it contains chat IDs, object keys and share tokens) and revert `database_id` to `""`:

   ```bash
   npx wrangler d1 execute tg-s3-self-db --remote --command "SELECT (SELECT count(*) FROM objects) AS objects, (SELECT count(*) FROM buckets) AS buckets"
   rm backup.sql
   ```

6. Re-run **Deploy to Cloudflare Workers**: it finds the new database by name and binds the Worker to it (the migrations are already applied).
7. Create new S3 keys in the Mini App and update your clients. When everything works, set `WEB_UPLOAD_BUCKET` back (or delete the Variable) and re-run the workflow.

## Local development

```bash
npm install
npx wrangler d1 migrations apply tg-s3-self-db --local
```

Create `.dev.vars` (git-ignored) with at least:

```bash
TG_BOT_TOKEN=123456:ABC-DEF...
DEFAULT_CHAT_ID=-1001234567890
```

Start the dev server:

```bash
X_LOCAL_EXPLORER=false npx wrangler dev
```

`X_LOCAL_EXPLORER=false` is needed because `database_id` is empty in `wrangler.toml`; with wrangler 4.90 a plain `wrangler dev` crashes with *"The expression evaluated to a falsy value: (databaseId)"*.

Type-check with `npm run typecheck`.

## Verify the deployment

```bash
# Webhook status (should show <WORKER_URL>/bot/webhook and no last_error_message)
curl "https://api.telegram.org/bot<TG_BOT_TOKEN>/getWebhookInfo"

# S3 API (create credentials first in the Mini App → Keys tab)
aws --endpoint-url https://files.example.com s3 ls
aws --endpoint-url https://files.example.com s3 mb s3://test
aws --endpoint-url https://files.example.com s3 cp file.txt s3://test/

# rclone
rclone config create tgs3 s3 provider=Other \
  access_key_id=YOUR_KEY secret_access_key=YOUR_SECRET \
  endpoint=https://files.example.com acl=private
rclone ls tgs3:test
```

Replace `https://files.example.com` with your Worker URL. Live logs: `npx wrangler tail tg-s3-self`; persisted Worker logs (cron results and errors, no per-request logs) are in the dashboard under the Worker's **Logs**. S3 compatibility details: [S3-COMPAT.md](S3-COMPAT.md).
