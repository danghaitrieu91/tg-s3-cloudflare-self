# Web Upload

**English** | [Tiếng Việt](web-upload.vi.md)

The Worker serves a simple drag-and-drop upload page at `/`. Anyone who opens it can upload a file (up to 20 MB) and gets back a public link to it. There is no login.

> [!WARNING]
> **Web upload is enabled by default and is public.**
> 1. **Anyone who knows your Worker URL can upload files** (≤ 20 MB each) and get public links. The Worker has **no login and no rate limit** for this page. It can be abused (spam, illegal content), which may get your Telegram bot or group banned.
> 2. **Protect it with Cloudflare**: a [WAF rate limiting rule](#option-1-waf-rate-limiting-rule) and/or [Cloudflare Access](#option-2-cloudflare-access). Both require a **custom domain** on a Cloudflare zone — they do not protect the `*.workers.dev` URL, so that URL must be turned off.
> 3. **Or disable it**: set the GitHub Variable `WEB_UPLOAD_BUCKET` to `off` and re-run the workflow (with `deploy.sh`: set `WEB_UPLOAD_BUCKET = "off"` in `wrangler.toml`).

## How it works

| Item | Behavior |
|------|----------|
| Routes | `GET /` (also `/index.html`) — the upload page; `POST /api/web-upload?name=<filename>` — the upload endpoint (raw file in the request body). The page is served only to unauthenticated requests: a signed S3 request to `/` (ListBuckets, e.g. `aws s3 ls`) or a presigned URL still reaches the S3 API |
| Default | **ON**: `WEB_UPLOAD_BUCKET = "files"` in `wrangler.toml` |
| Size limit | 20 MB, checked on the `Content-Length` header and on the bytes actually received (`413` if larger) |
| Authentication | None. No built-in rate limit |
| Bucket | Value of `WEB_UPLOAD_BUCKET` (lower-cased). It must be a valid bucket name (`^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$` after lower-casing), otherwise uploads fail with `500`. If the bucket does not exist, it is created on the first upload as a **public** bucket in `DEFAULT_CHAT_ID` (one atomic insert, so concurrent first uploads cannot create it twice) |
| Existing private bucket | Never made public. Uploads fail with `403` (`Web upload bucket is private; make it public or set WEB_UPLOAD_BUCKET=off`) |
| Object key | `YYYYMMDD_<sanitized-name>_<4 random hex>.<ext>`, e.g. `20261009_holiday_photo_3f9a.jpg`. The extension is sanitized like the name (only `a-z`, `0-9`, `.`, `-` are kept) |
| Content-Type | The declared type is kept only for images (`png`, `jpeg`, `gif`, `webp`, `avif`, `bmp`, `heic`, `heif`), `video/*`, `audio/*`, `application/pdf` and `text/plain`. Everything else (HTML, SVG, JavaScript, XML, unknown types) is stored as `application/octet-stream`, so browsers download it instead of rendering it. This stops the page from being used to host phishing pages or scripts on your domain |
| Returned link | `https://<worker-host>/<bucket>/<key>` — readable by anyone, because the bucket is public |

The uploaded files are normal objects: you can also see and delete them with the bot, the Mini App or any S3 client.

## Turning it off or changing the bucket

`WEB_UPLOAD_BUCKET` accepts:

| Value | Result |
|-------|--------|
| unset / `files` | ON, bucket `files` (default) |
| `off` (any case) or empty | OFF: `/` and `/api/web-upload` are not served by the web upload feature |
| any other valid bucket name | ON, uploads go to that bucket |

### GitHub Actions

Fork → **Settings → Secrets and variables → Actions → Variables** → set `WEB_UPLOAD_BUCKET` (for example `off`), then re-run the **Deploy to Cloudflare Workers** workflow. The run prints a notice telling you whether web upload is ON or OFF. Deleting the Variable falls back to the `wrangler.toml` value (`files`).

### deploy.sh and wrangler.toml

`deploy.sh` does **not** read `WEB_UPLOAD_BUCKET` from `.env`. Edit `wrangler.toml` and run `./deploy.sh` again:

```toml
[vars]
WEB_UPLOAD_BUCKET = "off"
```

## Protecting web upload

### Before you start: custom domain and workers.dev

- WAF rate limiting rules are created per **zone** (your domain) in the dashboard ([Create a rate limiting rule in the dashboard](https://developers.cloudflare.com/waf/rate-limiting-rules/create-zone-dashboard/)), and a self-hosted Access application needs a domain that is an active zone in your Cloudflare account ([Publish a self-hosted application](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/self-hosted-public-app/)). So first serve the Worker on a custom domain, e.g. `files.example.com`.
- The protections below apply to that hostname only. If `tg-s3-self.<your-subdomain>.workers.dev` stays enabled, it is a second, **unprotected** way to reach `/api/web-upload`. Turn it off:
  - **GitHub Actions**: setting the Variable `CUSTOM_DOMAIN` makes CI add the Custom Domain and set `workers_dev = false` automatically.
  - **`deploy.sh`**: add the route and `workers_dev = false` to `wrangler.toml` yourself (see [deployment.md](deployment.md#custom-domain-and-tunnel)).
- Setting `workers_dev = false` disables the `workers.dev` route on the next deploy; disabling it only in the dashboard is undone by the next `wrangler deploy`. Version and Preview URLs are not disabled by this setting ([workers.dev](https://developers.cloudflare.com/workers/configuration/routing/workers-dev/)).

### Option 1: WAF rate limiting rule

A rate limiting rule limits how fast one client can upload. It slows abuse down; it does not stop a patient attacker (use Access for that).

What the **Free** plan allows (source: [Rate limiting rules — Availability](https://developers.cloudflare.com/waf/rate-limiting-rules/)):

| Setting | Free plan |
|---------|-----------|
| Number of rules | 1 |
| Fields in the rule expression | Path, Verified Bot |
| Counting characteristic | IP |
| Counting period | 10 s |
| Mitigation timeout (duration) | 10 s |

Steps (source: [Create a rate limiting rule in the dashboard](https://developers.cloudflare.com/waf/rate-limiting-rules/create-zone-dashboard/)):

1. Cloudflare dashboard → select your domain → **Security rules** page.
2. **Create rule** → **Rate limiting rules**.
3. **Rule name**: `web-upload`.
4. Expression: **Field** `URI Path`, **Operator** `equals`, **Value** `/api/web-upload`.
5. **With the same characteristics**: `IP`.
6. **When rate exceeds**: e.g. `5` requests per `10 seconds`.
7. **Then take action**: `Block`; **Duration**: `10 seconds`.
8. **Deploy**.

Cloudflare's counters are per data center and updated with a delay of up to a few seconds, so a few extra requests can still get through ([Rate limiting rules — Important remarks](https://developers.cloudflare.com/waf/rate-limiting-rules/)). Paid plans allow longer periods and timeouts (same source).

### Option 2: Cloudflare Access

Cloudflare Access puts a sign-in in front of a URL, so only people you allow (for example your own email address) can upload.

**Protect only the path `/api/web-upload`.** Do not protect the whole hostname:

- An Access application with an empty **Path**, or with `/*`, covers **every** path of the hostname ([Application paths](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/app-paths/)). That would block Telegram's calls to `/bot/webhook` (the bot stops working), S3 clients (bucket/object paths), public share links (`/share/*`), public bucket links and the Mini App — none of them can sign in.
- A more specific path inherits the rules of a parent path unless it has its own rule, so an application on `/api/web-upload` also covers anything under `/api/web-upload/` and nothing else ([Application paths](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/app-paths/)).
- Access cannot protect just the page `/` without also covering all paths below it. That is fine: protecting the endpoint is enough — the page stays visible, but uploads require sign-in.
- Do **not** use **Workers & Pages → your Worker → Access → Protect this Worker behind Access**. That protects every domain of the Worker (routes, Custom Domains, `workers.dev`, previews) — the whole bot and S3 API ([Cloudflare Access for Workers](https://developers.cloudflare.com/workers/configuration/cloudflare-access/)). Use a hostname/path application instead (same page, section "Protect a specific hostname, Custom Domain, or path").

Steps (source: [Publish a self-hosted application](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/self-hosted-public-app/); Zero Trust must be set up on the account first, see [Cloudflare Access for Workers — Before you start](https://developers.cloudflare.com/workers/configuration/cloudflare-access/)):

1. Cloudflare dashboard → **Zero Trust** → **Access controls** → **Applications** → **Create new application**.
2. Select **Self-hosted and private** → **Add public hostname**.
3. **Domain**: your custom domain (e.g. subdomain `files`, domain `example.com`); **Path**: `api/web-upload`.
4. **Access policies**: create an **Allow** policy that includes your email address(es). Access applications deny everyone who does not match an Allow policy.
5. Choose the identity provider(s) users sign in with.
6. **Create**.

Using it: the upload page sends the file with a background request, which cannot show a login page. Without a valid `CF_Authorization` cookie, Access blocks the request ([Authorization cookie](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/)). So:

1. Open `https://files.example.com/api/web-upload` in the browser once and sign in. (After sign-in the Worker may show an error for that URL — it only accepts `POST`. That is expected.)
2. Go to `https://files.example.com/` and upload as usual.

The `CF_Authorization` cookie is scoped to the hostname unless **Cookie Path Attribute** is enabled in the application's cookie settings — leave it off, otherwise the cookie would not be sent from the page at `/` ([Authorization cookie — Cookie Path Attribute](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/)). Sign in again when the session expires (24 hours by default, same source).

### Option 3: Disable it

If you do not need the page, turn it off — see [Turning it off or changing the bucket](#turning-it-off-or-changing-the-bucket). You can still upload with the bot, the Mini App or any S3 client.

## Errors

| Status | Response `error` | Meaning |
|--------|------------------|---------|
| `400` | `Empty file` | The request body was empty |
| `403` | `Web upload bucket is private; make it public or set WEB_UPLOAD_BUCKET=off` | The configured bucket already exists and is private |
| `413` | `File exceeds 20MB limit` | File larger than 20 MB |
| `500` | `WEB_UPLOAD_BUCKET is not a valid bucket name` | `WEB_UPLOAD_BUCKET` is not a valid bucket name; fix the Variable / `wrangler.toml` value and redeploy |
| `500` | `Storage bucket not configured` | The bucket could not be created or read |
| `500` | `Failed to upload file to backend` | Sending the file to Telegram or saving metadata failed (check `npx wrangler tail tg-s3-self`) |

Related: [configuration.md](configuration.md), [deployment.md](deployment.md).
