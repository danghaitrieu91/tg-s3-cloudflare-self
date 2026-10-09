#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# tg-s3-self one-click deploy script
#
# Usage: ./deploy.sh
#   Auto-detects the runtime environment:
#   - Host + Docker available: build images + deploy Worker + start all services
#   - Host without Docker:     deploy Worker with local wrangler
#   - Inside a Docker container: deploy Worker only (invoked by host orchestration)
#
# Optional arguments:
#   --vps    Legacy SSH deploy mode (no Docker)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---- Colors ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[!!]${NC} $1"; }
err()  { echo -e "${RED}[ERR]${NC} $1" >&2; }
step() { echo -e "\n${CYAN}==>${NC} $1"; }

gen_random() {
  local len="${1:-32}"
  LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$len" 2>/dev/null || \
    openssl rand -base64 "$((len * 2))" | tr -dc 'A-Za-z0-9' | head -c "$len"
}

# ---- Environment detection ----
IN_CONTAINER=0
if [ -f /.dockerenv ] || grep -qsE 'docker|containerd' /proc/1/cgroup 2>/dev/null; then
  IN_CONTAINER=1
fi

# ---- Load .env ----
if [ ! -f .env ]; then
  err ".env file not found. Copy .env.example to .env and fill in the configuration:"
  err "  cp .env.example .env && vim .env"
  exit 1
fi

set -a
source .env
set +a

# Backward compatibility with legacy CF_ACCOUNT_ID (wrangler 4.x requires CLOUDFLARE_ACCOUNT_ID)
if [ -n "${CF_ACCOUNT_ID:-}" ] && [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
  CLOUDFLARE_ACCOUNT_ID="$CF_ACCOUNT_ID"
  export CLOUDFLARE_ACCOUNT_ID
fi

# ---- Helper functions ----
# Cross-platform sed -i (macOS needs -i '', Linux needs -i)
sed_inplace() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

derive_webhook_secret() {
  node -e "const c=require('crypto');console.log(c.createHmac('sha256',process.env.TG_BOT_TOKEN).update('tg-s3-webhook').digest('hex'))"
}

# HTTP request (Node.js fetch instead of curl; curl inside Docker containers has SSL/CA compatibility issues)
_fetch() {
  local method="GET" url="" body=""
  local -a headers=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -s) shift ;;
      -X) method="$2"; shift 2 ;;
      -H) headers+=("$2"); shift 2 ;;
      -d) body="$2"; shift 2 ;;
      *)  url="$1"; shift ;;
    esac
  done
  node -e "
    (async () => {
      const [url, method, body, ...hdrs] = process.argv.slice(1);
      const headers = {};
      for (const h of hdrs) { const i = h.indexOf(': '); if (i > 0) headers[h.slice(0,i)] = h.slice(i+2); }
      const opts = { method, headers };
      if (body) opts.body = body;
      const r = await fetch(url, opts);
      process.stdout.write(await r.text());
    })().catch(e => { process.stderr.write(e.message + '\n'); process.exit(1); });
  " "$url" "$method" "$body" ${headers[@]+"${headers[@]}"}
}

# Persist a value to .env (update if present, append otherwise)
# Rewrites line by line to avoid sed special-character escaping issues
persist_env() {
  local key="$1" val="$2"
  if grep -q "^${key}=" .env 2>/dev/null; then
    # Line-by-line rewrite: avoids sed escaping issues with special characters like | & \ in val
    local tmpfile
    tmpfile=$(mktemp "${TMPDIR:-/tmp}/env.XXXXXX")
    while IFS= read -r line || [ -n "$line" ]; do
      if [[ "$line" == "${key}="* ]]; then
        echo "${key}=${val}"
      else
        echo "$line"
      fi
    done < .env > "$tmpfile"
    if cat "$tmpfile" > .env; then
      rm -f "$tmpfile"
    else
      rm -f "$tmpfile"
      return 1
    fi
  else
    echo "${key}=${val}" >> .env
  fi
}

# ---- Interactive configuration ----
INTERACTIVE=0
if [ "$IN_CONTAINER" -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
  INTERACTIVE=1
fi

open_url() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    open "$1" 2>/dev/null &
  elif command -v xdg-open &>/dev/null; then
    xdg-open "$1" 2>/dev/null &
  fi
}

ask_value() {
  local var_name="$1" prompt="$2" value
  read -rp "  $prompt: " value
  if [ -n "$value" ]; then
    eval "$var_name=\"\$value\""
    export "$var_name"
    persist_env "$var_name" "$value"
  fi
}

ask_yn() {
  local prompt="$1" default="${2:-Y}" choice
  read -rp "$(echo -e "${CYAN}?${NC}") $prompt [${default}]: " choice
  [[ "${choice:-$default}" =~ ^[Yy]$ ]]
}

interactive_setup() {
  step "Checking environment configuration"

  # -- Required --

  if [ -n "${TG_BOT_TOKEN:-}" ]; then
    log "TG_BOT_TOKEN ✓"
  else
    warn "TG_BOT_TOKEN is not set (required)"
    echo "  1. In Telegram, open @BotFather and send /newbot"
    echo "  2. Follow the prompts to create a bot, then copy the generated token"
    if [ "$INTERACTIVE" -eq 1 ]; then
      open_url "https://t.me/BotFather"
      ask_value TG_BOT_TOKEN "Enter Bot Token"
    fi
  fi

  if [ -n "${DEFAULT_CHAT_ID:-}" ]; then
    log "DEFAULT_CHAT_ID ✓"
  else
    warn "DEFAULT_CHAT_ID is not set (required)"
    echo "  1. Create a Telegram group and add the bot as an administrator"
    echo "  2. Send a message in the group"
    if [ -n "${TG_BOT_TOKEN:-}" ]; then
      echo "  3. Open the link below and find chat.id in the JSON:"
      echo "     https://api.telegram.org/bot${TG_BOT_TOKEN}/getUpdates"
      if [ "$INTERACTIVE" -eq 1 ]; then
        open_url "https://api.telegram.org/bot${TG_BOT_TOKEN}/getUpdates"
      fi
    else
      echo "  3. Set TG_BOT_TOKEN first, then get it via the getUpdates API"
    fi
    if [ "$INTERACTIVE" -eq 1 ]; then
      ask_value DEFAULT_CHAT_ID "Enter Chat ID (e.g. -1001234567890)"
    fi
  fi

  if [ -n "${TG_ADMIN_IDS:-}" ]; then
    log "TG_ADMIN_IDS ✓"
  else
    warn "TG_ADMIN_IDS is not set (required)"
    echo "  Comma-separated Telegram user IDs allowed to control the bot (e.g. 123456789,987654321)"
    echo "  Get your user ID by sending any message to @userinfobot"
    if [ "$INTERACTIVE" -eq 1 ]; then
      ask_value TG_ADMIN_IDS "Enter admin user IDs"
    fi
  fi

  # -- Optional features --

  if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
    log "CLOUDFLARE_API_TOKEN ✓"
  elif [ "$INTERACTIVE" -eq 1 ]; then
    echo ""
    if ask_yn "Configure a Cloudflare API Token? (required for Docker deploy)" "Y"; then
      echo "  1. Create a custom API Token"
      echo "  2. Permissions: Workers Scripts:Edit, D1:Edit, R2:Edit, Account Settings:Read"
      echo "     For tunnel, also add: Cloudflare Tunnel:Edit, DNS:Edit"
      open_url "https://dash.cloudflare.com/profile/api-tokens"
      ask_value CLOUDFLARE_API_TOKEN "Enter API Token"
    fi
  fi

  if [ -n "${CF_CUSTOM_DOMAIN:-}" ]; then
    log "CF_CUSTOM_DOMAIN = ${CF_CUSTOM_DOMAIN} ✓"
  elif [ "$INTERACTIVE" -eq 1 ]; then
    echo ""
    if ask_yn "Use a custom domain? (also enables Cloudflare Tunnel)" "Y"; then
      ask_value CF_CUSTOM_DOMAIN "Enter domain (e.g. s3.example.com)"
    fi
  fi

  if [ -n "${TELEGRAM_API_ID:-}" ] && [ -n "${TELEGRAM_API_HASH:-}" ]; then
    log "Telegram Local Bot API ✓ (2GB file support)"
  elif [ "$INTERACTIVE" -eq 1 ]; then
    echo ""
    echo "  Local Bot API raises the file size limit from 20MB to 2GB"
    if ask_yn "Enable Telegram Local Bot API?" "Y"; then
      echo "  1. Log in to my.telegram.org with your phone number"
      echo "  2. Choose 'API development tools'"
      echo "  3. Create an app to get api_id and api_hash"
      open_url "https://my.telegram.org"
      ask_value TELEGRAM_API_ID "Enter API ID (digits only)"
      ask_value TELEGRAM_API_HASH "Enter API Hash"
    fi
  fi

  echo ""
}

# Run interactive setup on the host (skipped inside containers)
if [ "$IN_CONTAINER" -eq 0 ]; then
  interactive_setup
fi

# ---- Auto-generate secrets ----
if [ -z "${VPS_SECRET:-}" ]; then
  VPS_SECRET="$(gen_random 48)"
  persist_env VPS_SECRET "$VPS_SECRET"
  log "Auto-generated VPS_SECRET"
fi
if [ -z "${SSE_MASTER_KEY:-}" ]; then
  SSE_MASTER_KEY="$(openssl rand -base64 32)"
  persist_env SSE_MASTER_KEY "$SSE_MASTER_KEY"
  log "Auto-generated SSE_MASTER_KEY"
fi

# ---- Telegram Local Bot API detection ----
HAS_LOCAL_API=0
if [ -n "${TELEGRAM_API_ID:-}" ] && [ -n "${TELEGRAM_API_HASH:-}" ]; then
  HAS_LOCAL_API=1
  TG_LOCAL_API="http://telegram-bot-api:8081"
  persist_env TG_LOCAL_API "$TG_LOCAL_API"
  log "Local Bot API enabled (2GB file support)"
elif [ -n "${TELEGRAM_API_ID:-}" ] || [ -n "${TELEGRAM_API_HASH:-}" ]; then
  # Only one of them is set; remind the user to complete it
  warn "TELEGRAM_API_ID and TELEGRAM_API_HASH must both be set; only one is currently set"
  warn "Local Bot API not enabled; file size limit is 20MB"
  TG_LOCAL_API="https://api.telegram.org"
else
  if [ -z "${TG_LOCAL_API:-}" ]; then
    TG_LOCAL_API="https://api.telegram.org"
  fi
  # Hint in non-interactive mode (interactive mode is handled in interactive_setup)
  if [ "$INTERACTIVE" -eq 0 ] && [ "$IN_CONTAINER" -eq 0 ]; then
    warn "TELEGRAM_API_ID/HASH not configured; file size limit is 20MB"
  fi
fi

# ---- Validate required settings ----
validate_required() {
  local missing=0
  for var in TG_BOT_TOKEN DEFAULT_CHAT_ID TG_ADMIN_IDS; do
    if [ -z "${!var:-}" ]; then
      err "Missing required setting: $var"
      missing=1
    fi
  done
  if [ $missing -eq 1 ]; then
    err "Fill in the required settings in .env, or re-run ./deploy.sh for interactive setup"
    exit 1
  fi
}

# ============================================================
# CF Worker deploy (runs inside the container or locally)
# ============================================================
deploy_cf() {
  step "Deploying Cloudflare Worker"

  if ! command -v npx &>/dev/null; then
    err "Node.js and npm are required; please install them first"
    exit 1
  fi

  # Install dependencies
  if [ ! -d node_modules ]; then
    step "Installing npm dependencies"
    npm install
    log "Dependencies installed"
  fi

  # Check wrangler authentication
  step "Checking Cloudflare authentication"
  if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
    log "Authenticating with CLOUDFLARE_API_TOKEN"
  elif ! npx wrangler whoami &>/dev/null 2>&1; then
    warn "wrangler is not logged in; opening browser for authorization..."
    npx wrangler login
  fi
  log "Cloudflare authentication OK"

  # Get or create the D1 database (fully automatic, safe for repeated deploys)
  # Priority: .env cache > wrangler.toml > remote lookup > create new
  CURRENT_DB_ID=$(sed -n 's/^database_id *= *"\([^"]*\)".*/\1/p' wrangler.toml | head -1)
  DB_ID=""

  if [ -n "$CURRENT_DB_ID" ]; then
    DB_ID="$CURRENT_DB_ID"
    log "D1 database already exists: $DB_ID"
  elif [ -n "${D1_DATABASE_ID:-}" ]; then
    DB_ID="$D1_DATABASE_ID"
    log "D1 database ID restored from .env: $DB_ID"
  else
    # First check whether a database with the same name already exists remotely
    step "Looking up D1 database tg-s3-self-db"
    DB_ID=$(npx wrangler d1 list --json 2>/dev/null | \
      node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); const db=d.find(x=>x.name==='tg-s3-self-db'); console.log(db?.uuid||'')" 2>/dev/null) || DB_ID=""

    if [ -z "$DB_ID" ]; then
      # Not found remotely; create a new database
      step "Creating D1 database tg-s3-self-db"
      DB_OUTPUT=$(npx wrangler d1 create tg-s3-self-db 2>&1) || true
      DB_ID=$(echo "$DB_OUTPUT" | grep -o 'database_id = "[^"]*"' | head -1 | sed 's/database_id = "\(.*\)"/\1/')
    fi

    if [ -z "$DB_ID" ]; then
      err "Could not get the D1 database ID"
      exit 1
    fi
    log "D1 database: $DB_ID"
  fi

  # Make sure wrangler.toml has the correct database_id
  if [ -z "$CURRENT_DB_ID" ]; then
    sed_inplace "s/database_id = \"\"/database_id = \"$DB_ID\"/" wrangler.toml
  fi

  # Persist to .env (wrangler.toml is not persisted inside Docker containers; .env is persisted via volume)
  persist_env D1_DATABASE_ID "$DB_ID"

  # Create the R2 cache bucket
  step "Creating R2 cache bucket tg-s3-self-cache"
  if npx wrangler r2 bucket list 2>&1 | grep -q 'tg-s3-self-cache'; then
    log "R2 cache bucket already exists"
  else
    npx wrangler r2 bucket create tg-s3-self-cache 2>&1 || true
    log "R2 cache bucket created"
  fi

  # R2 lifecycle: 90-day fallback GC
  step "Configuring R2 fallback cleanup policy (90 days)"
  LIFECYCLE_OUT=$(npx wrangler r2 bucket lifecycle add tg-s3-self-cache "cache-gc" \
    --expire-days 90 2>&1) || true
  if echo "$LIFECYCLE_OUT" | grep -q "Rule IDs must be unique"; then
    log "R2 lifecycle rule already exists"
  else
    log "R2 lifecycle rule set"
  fi

  # Apply database migrations
  step "Applying D1 database migrations"
  if npx wrangler d1 migrations apply tg-s3-self-db --remote 2>&1; then
    log "Database migrations applied"
  else
    warn "Database migrations may have failed (ignore if already up to date)"
  fi

  # Set secrets
  step "Configuring Worker secrets"
  echo "$TG_BOT_TOKEN" | npx wrangler secret put TG_BOT_TOKEN 2>&1 || true
  echo "$DEFAULT_CHAT_ID" | npx wrangler secret put DEFAULT_CHAT_ID 2>&1 || true
  if [ -n "${VPS_URL:-}" ]; then
    echo "$VPS_URL" | npx wrangler secret put VPS_URL 2>&1 || true
  fi
  echo "$VPS_SECRET" | npx wrangler secret put VPS_SECRET 2>&1 || true
  if [ -n "${SSE_MASTER_KEY:-}" ]; then
    echo "$SSE_MASTER_KEY" | npx wrangler secret put SSE_MASTER_KEY 2>&1 || true
  fi
  if [ -n "${TG_ADMIN_IDS:-}" ]; then
    echo "$TG_ADMIN_IDS" | npx wrangler secret put TG_ADMIN_IDS 2>&1 || true
  fi
  log "Secrets configured"

  # Deploy the Worker
  step "Deploying Worker"
  if ! DEPLOY_OUTPUT=$(npx wrangler deploy 2>&1); then
    err "Worker deploy failed:"
    echo "$DEPLOY_OUTPUT" >&2
    exit 1
  fi
  echo "$DEPLOY_OUTPUT"

  WORKER_URL=$(echo "$DEPLOY_OUTPUT" | grep -oE 'https://[^ ]+\.workers\.dev' | head -1) || WORKER_URL=""
  if [ -n "$WORKER_URL" ]; then
    log "Worker deployed: $WORKER_URL"
  else
    log "Worker deploy finished"
  fi

  if [ -n "${CF_CUSTOM_DOMAIN:-}" ] && ! grep -qF "pattern = \"$CF_CUSTOM_DOMAIN\"" wrangler.toml; then
    warn "CF_CUSTOM_DOMAIN=$CF_CUSTOM_DOMAIN has no [[routes]] entry in wrangler.toml: the Worker is NOT served there,"
    warn "  so WORKER_URL and the Telegram webhook below will not work. Add the route (see docs/deployment.md) and re-run."
  fi

  # Set the WORKER_URL secret
  EFFECTIVE_URL="${CF_CUSTOM_DOMAIN:+https://$CF_CUSTOM_DOMAIN}"
  EFFECTIVE_URL="${EFFECTIVE_URL:-$WORKER_URL}"
  if [ -n "$EFFECTIVE_URL" ]; then
    step "Setting WORKER_URL secret"
    echo "$EFFECTIVE_URL" | npx wrangler secret put WORKER_URL 2>&1 || true
    log "WORKER_URL = $EFFECTIVE_URL"
  fi

  # Register the Telegram webhook
  if [ -n "$EFFECTIVE_URL" ]; then
    step "Registering Telegram Bot webhook"
    WEBHOOK_URL="$EFFECTIVE_URL/bot/webhook"
    WEBHOOK_SECRET=$(TG_BOT_TOKEN="$TG_BOT_TOKEN" derive_webhook_secret)
    WEBHOOK_RES=$(_fetch -X POST \
      "https://api.telegram.org/bot${TG_BOT_TOKEN}/setWebhook" \
      -H "Content-Type: application/json" \
      -d "{\"url\":\"${WEBHOOK_URL}\",\"secret_token\":\"${WEBHOOK_SECRET}\"}" 2>&1) || true
    if echo "$WEBHOOK_RES" | grep -q '"ok":true'; then
      log "Webhook registered: $WEBHOOK_URL"
    else
      warn "Webhook registration failed"
      if [ -n "$WEBHOOK_RES" ]; then
        warn "  Response: $WEBHOOK_RES"
      else
        warn "  Could not reach api.telegram.org (network issue?)"
      fi
    fi
  fi

  # Custom domain (CF_CUSTOM_DOMAIN) is NOT routed by this script: add [[routes]] (custom_domain = true)
  # and set workers_dev = false in wrangler.toml yourself (see docs/deployment.md)
}

# ============================================================
# Automatic Cloudflare Tunnel creation
# After creation, CF_TUNNEL_TOKEN is written to .env (persisted when mounted as a volume)
# ============================================================
setup_tunnel() {
  step "Configuring Cloudflare Tunnel"

  if [ -n "${CF_TUNNEL_TOKEN:-}" ]; then
    log "CF_TUNNEL_TOKEN already set; skipping tunnel creation"
    return 0
  fi

  if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
    warn "Skipping automatic tunnel creation (requires CLOUDFLARE_API_TOKEN)"
    warn "Create manually: CF Dashboard > Zero Trust > Tunnels, then set CF_TUNNEL_TOKEN"
    return 1
  fi

  if [ -z "${CF_CUSTOM_DOMAIN:-}" ]; then
    warn "CF_CUSTOM_DOMAIN is required to assign a hostname to the tunnel"
    warn "Or create one manually in CF Dashboard > Zero Trust > Tunnels and set CF_TUNNEL_TOKEN"
    return 1
  fi

  local CF_API="https://api.cloudflare.com/client/v4"
  local AUTH_HEADER="Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"

  # Get the Account ID
  local ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-${CF_ACCOUNT_ID:-}}"
  if [ -z "$ACCOUNT_ID" ]; then
    step "Getting Cloudflare Account ID"
    ACCOUNT_ID=$(_fetch "$CF_API/accounts" -H "$AUTH_HEADER" | \
      node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.result?.[0]?.id||'')" 2>/dev/null) || ACCOUNT_ID=""
    if [ -z "$ACCOUNT_ID" ]; then
      warn "Could not get the Account ID; set CF_ACCOUNT_ID in .env"
      return 1
    fi
    log "Account ID: ${ACCOUNT_ID:0:8}..."
  fi

  # Check whether a tunnel with the same name already exists
  step "Checking existing tunnels"
  local LIST_RESP=""
  LIST_RESP=$(_fetch "$CF_API/accounts/$ACCOUNT_ID/cfd_tunnel?name=tg-s3-self&is_deleted=false" \
    -H "$AUTH_HEADER" 2>&1) || true
  local EXISTING=""
  EXISTING=$(echo "$LIST_RESP" | \
    node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); const t=d.result?.find(t=>t.name==='tg-s3-self'); console.log(t?.id||'')" 2>/dev/null) || EXISTING=""

  local TUNNEL_ID=""
  local TUNNEL_TOKEN_FROM_CREATE=""
  if [ -n "$EXISTING" ]; then
    TUNNEL_ID="$EXISTING"
    log "Existing tunnel tg-s3-self: ${TUNNEL_ID:0:8}..."
  else
    # Check API permissions (a failed list means the token lacks permission)
    if echo "$LIST_RESP" | grep -q '"success":false'; then
      warn "API Token is missing the Cloudflare Tunnel permission"
      warn "Add it in CF Dashboard > My Profile > API Tokens:"
      warn "  Account | Cloudflare Tunnel | Edit"
      warn "Response: $LIST_RESP"
      return 1
    fi

    step "Creating Cloudflare Tunnel: tg-s3-self"
    local CREATE_RESP=""
    CREATE_RESP=$(_fetch -X POST "$CF_API/accounts/$ACCOUNT_ID/cfd_tunnel" \
      -H "$AUTH_HEADER" \
      -H "Content-Type: application/json" \
      -d '{"name":"tg-s3-self","config_src":"cloudflare"}' 2>&1) || true
    TUNNEL_ID=$(echo "$CREATE_RESP" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.result?.id||'')" 2>/dev/null) || TUNNEL_ID=""
    # The create response already contains the token; no separate fetch needed
    TUNNEL_TOKEN_FROM_CREATE=$(echo "$CREATE_RESP" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.result?.token||'')" 2>/dev/null) || TUNNEL_TOKEN_FROM_CREATE=""
    if [ -z "$TUNNEL_ID" ]; then
      warn "Tunnel creation failed"
      if echo "$CREATE_RESP" | grep -q '"code":10000'; then
        warn "API Token lacks permission; Cloudflare Tunnel: Edit is required"
      fi
      [ -n "$CREATE_RESP" ] && warn "Response: $CREATE_RESP"
      return 1
    fi
    log "Tunnel created: ${TUNNEL_ID:0:8}..."
  fi

  # Configure tunnel ingress
  local TUNNEL_HOSTNAME="vps.${CF_CUSTOM_DOMAIN}"
  step "Configuring tunnel ingress: $TUNNEL_HOSTNAME -> processor:3000"
  _fetch -X PUT "$CF_API/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d "{\"config\":{\"ingress\":[{\"hostname\":\"$TUNNEL_HOSTNAME\",\"service\":\"http://processor:3000\",\"originRequest\":{\"noTLSVerify\":true}},{\"service\":\"http_status:404\"}]}}" >/dev/null 2>&1 || true
  log "Tunnel ingress configured"

  # Create the DNS CNAME
  step "Configuring DNS: $TUNNEL_HOSTNAME -> tunnel"
  local ZONE_ID=""
  local DOMAIN="$CF_CUSTOM_DOMAIN"
  while [ -n "$DOMAIN" ] && [ -z "$ZONE_ID" ]; do
    ZONE_ID=$(_fetch "$CF_API/zones?name=$DOMAIN" -H "$AUTH_HEADER" | \
      node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.result?.[0]?.id||'')" 2>/dev/null) || ZONE_ID=""
    if [ -z "$ZONE_ID" ]; then
      DOMAIN="${DOMAIN#*.}"
      if [[ "$DOMAIN" != *.* ]]; then break; fi
    fi
  done

  if [ -n "$ZONE_ID" ]; then
    local EXISTING_DNS
    EXISTING_DNS=$(_fetch "$CF_API/zones/$ZONE_ID/dns_records?name=$TUNNEL_HOSTNAME&type=CNAME" \
      -H "$AUTH_HEADER" | \
      node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.result?.[0]?.id||'')" 2>/dev/null) || EXISTING_DNS=""

    if [ -n "$EXISTING_DNS" ]; then
      _fetch -X PUT "$CF_API/zones/$ZONE_ID/dns_records/$EXISTING_DNS" \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -d "{\"type\":\"CNAME\",\"name\":\"$TUNNEL_HOSTNAME\",\"content\":\"$TUNNEL_ID.cfargotunnel.com\",\"proxied\":true}" >/dev/null 2>&1 || true
      log "DNS record updated: $TUNNEL_HOSTNAME"
    else
      _fetch -X POST "$CF_API/zones/$ZONE_ID/dns_records" \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -d "{\"type\":\"CNAME\",\"name\":\"$TUNNEL_HOSTNAME\",\"content\":\"$TUNNEL_ID.cfargotunnel.com\",\"proxied\":true}" >/dev/null 2>&1 || true
      log "DNS record created: $TUNNEL_HOSTNAME"
    fi
  else
    warn "Could not find the CF zone for domain $CF_CUSTOM_DOMAIN"
    warn "Add the DNS CNAME manually: $TUNNEL_HOSTNAME -> $TUNNEL_ID.cfargotunnel.com"
  fi

  # Get the tunnel token (prefer the token from the create response)
  if [ -n "$TUNNEL_TOKEN_FROM_CREATE" ]; then
    CF_TUNNEL_TOKEN="$TUNNEL_TOKEN_FROM_CREATE"
    log "Tunnel token taken from the create response"
  else
    step "Getting tunnel connector token"
    local TOKEN_RESP=""
    TOKEN_RESP=$(_fetch "$CF_API/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/token" \
      -H "$AUTH_HEADER" 2>&1) || true
    CF_TUNNEL_TOKEN=$(echo "$TOKEN_RESP" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.result||'')" 2>/dev/null) || CF_TUNNEL_TOKEN=""
    if [ -z "$CF_TUNNEL_TOKEN" ]; then
      warn "Could not get the tunnel token"
      [ -n "$TOKEN_RESP" ] && warn "Response: $TOKEN_RESP"
      warn "Get the token in CF Dashboard > Zero Trust > Tunnels > tg-s3-self"
      return 1
    fi
    log "Tunnel token obtained"
  fi

  # Write to .env (persisted to the host automatically when mounted as a volume)
  persist_env CF_TUNNEL_TOKEN "$CF_TUNNEL_TOKEN"
  log "CF_TUNNEL_TOKEN written to .env"

  # Set VPS_URL to the tunnel hostname
  VPS_URL="https://$TUNNEL_HOSTNAME"
  persist_env VPS_URL "$VPS_URL"
  log "VPS_URL set to: $VPS_URL"

  # Sync to Worker secrets
  echo "$VPS_URL" | npx wrangler secret put VPS_URL 2>&1 || true
  log "VPS_URL secret updated"
}

# ============================================================
# Fully automated Docker orchestration (runs on the host)
# ============================================================
deploy_docker() {
  # Check CLOUDFLARE_API_TOKEN (required in Docker mode)
  if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
    err "Docker deploy requires CLOUDFLARE_API_TOKEN"
    err "Set it in .env, or deploy with local wrangler:"
    err "  npm install && npx wrangler login && npx wrangler deploy"
    exit 1
  fi

  # Build images one at a time (avoids a BuildKit parallel build bug)
  step "Building Docker image (deploy)"
  if ! docker compose build deploy; then
    err "deploy image build failed"
    exit 1
  fi

  step "Building Docker image (processor)"
  if ! docker compose build processor; then
    err "processor image build failed"
    exit 1
  fi

  # Deploy the CF Worker + configure the Tunnel via the deploy container
  # The .env file is mounted into the container as a volume; changes made inside (CF_TUNNEL_TOKEN etc.) persist automatically
  step "Deploying CF Worker"
  if ! docker compose --profile deploy run --rm -T deploy; then
    err "CF Worker deploy failed; check the logs"
    exit 1
  fi

  # Reload .env (the container may have written CF_TUNNEL_TOKEN, VPS_URL, VPS_SECRET)
  set -a
  source .env
  set +a

  # Start long-running services
  step "Starting services"
  COMPOSE_PROFILES=""
  if [ -n "${CF_TUNNEL_TOKEN:-}" ]; then
    COMPOSE_PROFILES="$COMPOSE_PROFILES --profile tunnel"
  fi
  if [ "$HAS_LOCAL_API" -eq 1 ]; then
    COMPOSE_PROFILES="$COMPOSE_PROFILES --profile localapi"
  fi

  if [ -n "$COMPOSE_PROFILES" ]; then
    docker compose $COMPOSE_PROFILES up -d
  else
    docker compose up -d processor
  fi

  # Status hints
  if [ -n "${CF_TUNNEL_TOKEN:-}" ] && [ "$HAS_LOCAL_API" -eq 1 ]; then
    log "processor + tunnel + telegram-bot-api started (2GB file support)"
  elif [ -n "${CF_TUNNEL_TOKEN:-}" ]; then
    log "processor + tunnel started"
    warn "Local Bot API not enabled; file size limit is 20MB"
  elif [ "$HAS_LOCAL_API" -eq 1 ]; then
    warn "Cloudflare Tunnel not configured (missing CF_CUSTOM_DOMAIN or insufficient API Token permissions)"
    warn "processor + telegram-bot-api started but not reachable from outside"
  else
    warn "Cloudflare Tunnel not configured (missing CF_CUSTOM_DOMAIN or insufficient API Token permissions)"
    warn "processor started but not reachable from outside"
    warn "To use a tunnel, set CF_CUSTOM_DOMAIN and re-run ./deploy.sh"
  fi

  # Wait for processor to be ready
  step "Checking processor health"
  sleep 2
  PROC_STATE=$(docker compose ps processor --format '{{.State}}' 2>/dev/null) || PROC_STATE=""
  if [ "$PROC_STATE" = "running" ]; then
    log "processor is running"
  elif docker compose ps processor 2>/dev/null | grep -qiE 'running|up'; then
    log "processor is running"
  else
    warn "processor state: ${PROC_STATE:-unknown}"
    warn "View logs: docker compose logs processor"
  fi
}

# ============================================================
# VPS SSH deploy (non-Docker mode)
# ============================================================
deploy_vps() {
  step "Deploying VPS processor service"

  if [ -z "${VPS_SSH:-}" ]; then
    err "VPS deploy requires VPS_SSH to be set (e.g. root@1.2.3.4)"
    exit 1
  fi

  VPS_DIR="${VPS_DEPLOY_DIR:-/opt/tg-s3-self}"

  # Test SSH connection
  step "Testing SSH connection: $VPS_SSH"
  if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$VPS_SSH" "echo ok" &>/dev/null; then
    err "SSH connection failed: $VPS_SSH"
    err "Make sure that:"
    err "  1. SSH keys are configured"
    err "  2. The target host is reachable"
    err "  3. VPS_SSH has the correct format (e.g. root@1.2.3.4)"
    exit 1
  fi
  log "SSH connection OK"

  # Check Docker
  step "Checking Docker on the VPS"
  if ! ssh "$VPS_SSH" "command -v docker &>/dev/null && docker compose version &>/dev/null"; then
    warn "Docker not detected on the VPS; installing..."
    ssh "$VPS_SSH" bash <<'INSTALL_DOCKER'
      curl -fsSL https://get.docker.com | sh
      systemctl enable docker
      systemctl start docker
INSTALL_DOCKER
    log "Docker installed"
  else
    log "Docker environment OK"
  fi

  # Create the deploy directory
  ssh "$VPS_SSH" "mkdir -p \"$VPS_DIR\""

  # Upload files
  step "Uploading processor service files"
  rsync -avz --delete \
    processor/package.json \
    processor/server.js \
    processor/Dockerfile \
    docker-compose.yml \
    "$VPS_SSH:$VPS_DIR/"

  # Upload .env
  step "Configuring VPS environment variables"
  ssh "$VPS_SSH" "cat > \"$VPS_DIR/.env\"" <<ENV_EOF
TG_BOT_TOKEN=$TG_BOT_TOKEN
VPS_SECRET=${VPS_SECRET:-}
DEFAULT_CHAT_ID=$DEFAULT_CHAT_ID
TG_LOCAL_API=${TG_LOCAL_API:-https://api.telegram.org}
TELEGRAM_API_ID=${TELEGRAM_API_ID:-}
TELEGRAM_API_HASH=${TELEGRAM_API_HASH:-}
PORT=${VPS_PORT:-3000}
ENV_EOF
  log "VPS environment variables configured"

  # Build and start
  step "Building and starting services"
  local VPS_PROFILES=""
  if [ "$HAS_LOCAL_API" -eq 1 ]; then
    VPS_PROFILES="--profile localapi"
  fi

  ssh "$VPS_SSH" bash <<DEPLOY_CMD
    cd "$VPS_DIR"
    docker compose down 2>/dev/null || true
    docker compose build --no-cache
    docker compose $VPS_PROFILES up -d
    echo "--- Service status ---"
    docker compose $VPS_PROFILES ps
DEPLOY_CMD
  log "VPS processor service started"

  # Health check
  step "VPS health check"
  sleep 3
  if ssh "$VPS_SSH" "curl -sf -o /dev/null http://127.0.0.1:${VPS_PORT:-3000}/api/jobs/nonexistent 2>/dev/null"; then
    log "VPS processor service is running"
  else
    if ssh "$VPS_SSH" "curl -sf -w '%{http_code}' -o /dev/null http://127.0.0.1:${VPS_PORT:-3000}/api/jobs/test 2>/dev/null" | grep -qE '40[0-9]'; then
      log "VPS processor service is running (API responding)"
    else
      warn "VPS service may not be ready yet; check the logs:"
      warn "  ssh $VPS_SSH 'cd $VPS_DIR && docker compose logs'"
    fi
  fi
}

# ============================================================
# Deploy summary
# ============================================================
print_summary() {
  echo ""
  echo -e "${GREEN}============================================================${NC}"
  echo -e "${GREEN}  tg-s3-self deploy complete${NC}"
  echo -e "${GREEN}============================================================${NC}"
  echo ""

  if [ -n "${EFFECTIVE_URL:-}" ]; then
    echo -e "  URL:         ${CYAN}${EFFECTIVE_URL}${NC}"
    echo -e "  Mini App:    ${CYAN}${EFFECTIVE_URL}/miniapp${NC}"
  elif [ -n "${WORKER_URL:-}" ]; then
    echo -e "  Worker URL:  ${CYAN}${WORKER_URL}${NC}"
    echo -e "  Mini App:    ${CYAN}${WORKER_URL}/miniapp${NC}"
  fi

  if [ -n "${VPS_URL:-}" ]; then
    echo -e "  Processor:   ${CYAN}${VPS_URL}${NC} (via Cloudflare Tunnel)"
  fi

  echo ""
  echo -e "  Create S3 credentials in the ${CYAN}Keys${NC} tab of the Telegram Mini App"
  echo ""
  echo "  Quick check:"
  echo "    rclone mkdir tg-s3:photos"
  echo "    rclone copy ./test.jpg tg-s3:photos/"
  echo "    rclone ls tg-s3:photos/"
  echo ""
  echo "  Common operations:"
  echo "    Redeploy after updating code:  git pull && ./deploy.sh"
  echo "    Restart services only:         docker compose --profile tunnel restart"
  echo "    View logs:                     docker compose --profile tunnel logs -f"
  echo "    Stop all services:             docker compose --profile tunnel down"
  echo ""
}

# ============================================================
# Main flow
# ============================================================
echo -e "${CYAN}"
echo "  ┌─────────────────────────────────────┐"
echo "  │   tg-s3-self deploy                  │"
echo "  │   Telegram-backed S3 Storage         │"
echo "  └─────────────────────────────────────┘"
echo -e "${NC}"

validate_required

if [ "$IN_CONTAINER" -eq 1 ]; then
  # ============================================
  # Inside container: deploy CF Worker + configure tunnel only
  # ============================================
  deploy_cf
  setup_tunnel || true
  print_summary
  exit 0
fi

# ============================================
# Host
# ============================================
case "${1:-}" in
  --vps)
    # Legacy SSH mode: deploy Worker with local wrangler + deploy VPS over SSH
    deploy_cf
    deploy_vps
    ;;
  *)
    # Auto-detect
    if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
      # Fully automated Docker orchestration
      deploy_docker
    else
      # No Docker: deploy Worker with local wrangler
      deploy_cf
    fi
    ;;
esac

print_summary
