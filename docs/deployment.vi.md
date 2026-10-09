# Hướng dẫn triển khai

[English](deployment.md) | **Tiếng Việt**

Có hai cách triển khai `tg-s3-cloudflare-self`:

| Cách | Thực hiện | Phù hợp khi |
|------|-----------|-------------|
| **A. GitHub Actions** (khuyến nghị) | Fork repo, thêm Secrets/Variables, chạy workflow | Chỉ cần Worker, file tối đa 20 MB, không cần cài gì trên máy |
| **B. `deploy.sh`** | Chạy script trên máy của bạn hoặc trên server (có hoặc không có Docker) | Cần thêm VPS processor (file tối đa 2 GB, xử lý media) |

Cả hai cách đều tạo cùng các tài nguyên Cloudflare:

| Tài nguyên | Tên |
|------------|-----|
| Worker | `tg-s3-self` |
| Cơ sở dữ liệu D1 | `tg-s3-self-db` |
| Bucket R2 (cache) | `tg-s3-self-cache` |

Toàn bộ tuỳ chọn cấu hình nằm trong [configuration.vi.md](configuration.vi.md). Trang tải lên công khai (web upload) **được bật sẵn** — hãy đọc [web-upload.vi.md](web-upload.vi.md) trước khi triển khai.

## Chuẩn bị

1. **Telegram bot** — tạo bằng [@BotFather](https://t.me/BotFather) (`/newbot`) và lưu lại token.
2. **Telegram supergroup** — tạo một nhóm, thêm bot làm **quản trị viên (admin)** và lấy chat ID của nhóm (số âm bắt đầu bằng `-100`, ví dụ `-1001234567890`). Cách lấy: tạm thêm [@userinfobot](https://t.me/userinfobot) vào nhóm, hoặc gửi một tin nhắn trong nhóm rồi mở `https://api.telegram.org/bot<TOKEN>/getUpdates` và tìm `chat.id`.
3. **User ID Telegram của bạn** — gửi một tin nhắn bất kỳ cho [@userinfobot](https://t.me/userinfobot). Giá trị này dùng cho `TG_ADMIN_IDS` (bắt buộc).
4. **Tài khoản Cloudflare** đã **kích hoạt R2** — R2 cần đăng ký (subscription) kể cả khi chỉ dùng hạn mức miễn phí: dashboard → **Storage & databases → R2 → Overview** → hoàn tất bước checkout. Nguồn: [R2 get started](https://developers.cloudflare.com/r2/get-started/).
5. Chỉ cho cách B / phát triển local: **Node.js 22+** (dự án dùng wrangler v4).

## Cách A: GitHub Actions

Workflow nằm ở `.github/workflows/deploy.yml`. Nó chạy mỗi khi push lên `main` và khi chạy tay, nhưng job sẽ bị **bỏ qua (skipped)** cho đến khi bạn đặt Variable `DEPLOY_ENABLED` của repo thành `true`.

> [!NOTE]
> Workflow chưa được tác giả template chạy thử trọn vẹn; lần chạy đầu tiên trên fork của bạn chính là lần kiểm tra thật. Nếu có bước lỗi, xem [Khắc phục sự cố (cách A)](#khắc-phục-sự-cố-cách-a).

### 1. Fork repository

Fork `tg-s3-cloudflare-self` về tài khoản GitHub của bạn (nút **Fork** trên trang repo). Nếu muốn sửa trên máy, clone bản fork:

```bash
git clone https://github.com/<your-github-user>/tg-s3-cloudflare-self.git
cd tg-s3-cloudflare-self
```

### 2. Đăng ký subdomain workers.dev (một lần)

Nếu triển khai **không** dùng tên miền riêng, tài khoản Cloudflare cần có subdomain `workers.dev`; nếu chưa có, `wrangler deploy` sẽ báo lỗi *"You need to register a workers.dev subdomain before publishing to workers.dev"*.

Trong Cloudflare dashboard, vào **Workers & Pages** và đặt **Your subdomain** (URL workers.dev có dạng `<tên-worker>.<subdomain-của-bạn>.workers.dev`). Nguồn: [workers.dev](https://developers.cloudflare.com/workers/configuration/routing/workers-dev/).

URL của Worker sẽ là `https://tg-s3-self.<subdomain-của-bạn>.workers.dev`.

### 3. Tạo Cloudflare API token

Trong Cloudflare dashboard mở **My Profile → API Tokens** (hoặc **Manage Account → API Tokens** nếu dùng account token) → **Create Token**. Nguồn: [Create API token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/).

Chọn **Create Custom Token** (hoặc bắt đầu từ template **Edit Cloudflare Workers** — template này **không** có quyền D1 nên phải thêm vào; nội dung template: [API token templates](https://developers.cloudflare.com/fundamentals/api/reference/template/)) và bảo đảm token có:

| Phạm vi | Quyền | Mức |
|---------|-------|-----|
| Account | Workers Scripts | Edit |
| Account | D1 | Edit |
| Account | Workers R2 Storage | Edit |
| Account | Account Settings | Read |
| Zone *(chỉ khi dùng `CUSTOM_DOMAIN`)* | DNS | Edit |
| Zone *(chỉ khi dùng `CUSTOM_DOMAIN`)* | Workers Routes | Edit |

Giới hạn **Account Resources** vào đúng tài khoản sẽ triển khai, và (nếu dùng) **Zone Resources** vào zone của tên miền riêng. Token chỉ hiện **một lần** duy nhất.

**Account ID**: dashboard → **Workers & Pages** → **Account Details** → sao chép **Account ID**. Nguồn: [Find account and zone IDs](https://developers.cloudflare.com/fundamentals/account/find-account-and-zone-ids/).

### 4. Thêm Secrets cho repository

Trong bản fork: **Settings → Secrets and variables → Actions → Secrets → New repository secret**.

| Secret | Bắt buộc | Giá trị |
|--------|----------|---------|
| `CLOUDFLARE_API_TOKEN` | Có | Token ở bước 3 |
| `CLOUDFLARE_ACCOUNT_ID` | Có | Account ID Cloudflare |
| `TG_BOT_TOKEN` | Có | Bot token từ @BotFather |
| `DEFAULT_CHAT_ID` | Có | Chat ID của supergroup, ví dụ `-1001234567890` (bot phải là admin) |
| `TG_ADMIN_IDS` | Có | Danh sách user ID Telegram được dùng bot và Mini App, cách nhau bằng dấu phẩy, ví dụ `123456789,987654321` |
| `SSE_MASTER_KEY` | Không | Khoá base64 32 byte cho mã hoá SSE-S3 (`openssl rand -base64 32`). Không có khoá này thì không dùng được SSE-S3. Đừng bao giờ đổi khoá sau khi đã có object được mã hoá. |
| `VPS_URL` | Không | URL công khai của VPS processor (xem cách B) |
| `VPS_SECRET` | Không | Khoá bí mật dùng chung với processor đó |

### 5. Thêm Variables cho repository

Cùng trang, tab **Variables** → **New repository variable**.

| Variable | Bắt buộc | Giá trị |
|----------|----------|---------|
| `DEPLOY_ENABLED` | Có | `true` — nếu không, job sẽ bị bỏ qua |
| `CUSTOM_DOMAIN` | Không | ví dụ `files.example.com` — hostname trần (không có `https://`, không có path) thuộc một zone trên **cùng** tài khoản Cloudflare. Khi đặt biến này, CI gắn Worker vào tên miền đó và tắt URL `*.workers.dev`. Hãy dùng một hostname riêng, chưa dùng (xem [Tên miền riêng](#tên-miền-riêng)) |
| `WEB_UPLOAD_BUCKET` | Không | Không đặt = `files` (web upload **BẬT**). `off` để tắt. Giá trị khác = tên bucket (phải là tên bucket hợp lệ). Xem [web-upload.vi.md](web-upload.vi.md) |

### 6. Bật Actions và chạy lần triển khai đầu tiên

1. Mở tab **Actions** của bản fork. GitHub tắt workflow trong các bản fork cho đến khi bạn xác nhận — bấm **I understand my workflows, go ahead and enable them**.
2. Chọn **Deploy to Cloudflare Workers** → **Run workflow** (nhánh `main`). Các lần push lên `main` sau đó sẽ tự động triển khai.
3. Khi lần chạy thành công (màu xanh), mở log của bước **Resolve Worker URL** để xem URL của Worker.
4. Gửi `/start` cho bot **trong chat riêng** (bot không trả lời trong nhóm). Menu lệnh của bot không được đăng ký tự động; nếu muốn, hãy đặt bằng @BotFather `/setcommands` — xem [bot-commands.vi.md](bot-commands.vi.md).
5. Mở Mini App (lệnh `/miniapp` hoặc `https://<worker-url>/miniapp`) → tab **Keys** để tạo thông tin đăng nhập S3.

### Workflow làm những gì

| Bước | Diễn giải |
|------|-----------|
| Validate required secrets | Báo lỗi `Missing required repository secret: <NAME>` nếu một trong các secret `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `TG_BOT_TOKEN`, `DEFAULT_CHAT_ID`, `TG_ADMIN_IDS` bị trống, và báo `Variable CUSTOM_DOMAIN must be a bare hostname …` nếu `CUSTOM_DOMAIN` không phải hostname trần |
| Ensure D1 database | Tìm `tg-s3-self-db` (`wrangler d1 list --json`), tạo mới nếu chưa có, rồi ghi ID vào `wrangler.toml` **chỉ trong workspace của CI** (không bao giờ commit). Báo lỗi `wrangler d1 list failed …` nếu chính bước tìm kiếm thất bại |
| Ensure R2 cache bucket | Tạo `tg-s3-self-cache`; lỗi "already exists" được coi là thành công |
| Configure custom domain | Chỉ khi có `CUSTOM_DOMAIN`: thêm `[[routes]] pattern = "<domain>" custom_domain = true` và đặt `workers_dev = false` (chỉ trong workspace) |
| Apply D1 migrations | `wrangler d1 migrations apply tg-s3-self-db --remote` |
| Deploy Worker | `wrangler deploy --secrets-file …`: secrets được tải lên cùng lúc với mã nguồn. Chỉ thêm `--var WEB_UPLOAD_BUCKET:<giá-trị>` khi Variable được đặt. In ra thông báo web upload đang BẬT hay TẮT |
| Resolve Worker URL | `https://<CUSTOM_DOMAIN>`, hoặc URL `*.workers.dev` lấy từ output của lệnh deploy, sau đó lưu thành secret `WORKER_URL` |
| Register Telegram webhook | Gọi `setWebhook` với `<WORKER_URL>/bot/webhook` và secret token suy ra từ bot token (HMAC-SHA256). Job thất bại nếu Telegram không trả về `ok` |

### Tên miền riêng

1. Tên miền phải là một zone đang hoạt động trên **cùng** tài khoản Cloudflare ([Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)).
2. Thêm quyền Zone (DNS: Edit, Workers Routes: Edit) cho zone đó vào API token.
3. Đặt Variable `CUSTOM_DOMAIN` (ví dụ `files.example.com`) rồi chạy lại workflow. Cloudflare sẽ tự tạo bản ghi DNS và chứng chỉ cho Custom Domain ([Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)).

> [!WARNING]
> **Hãy dùng một hostname riêng, chưa dùng cho việc gì.** Trong CI (không tương tác), wrangler deploy với các cờ ghi đè (override), nên không hỏi trước khi chiếm hostname: bản ghi DNS đang có, hoặc Custom Domain của một Worker khác trên hostname đó, sẽ bị âm thầm trỏ sang Worker này. Tuyệt đối không đặt `CUSTOM_DOMAIN` thành hostname đang phục vụ thứ khác (website, ứng dụng hay Worker khác).

CI cũng đặt `workers_dev = false`, nên từ lần triển khai đó URL `*.workers.dev` không còn phục vụ Worker nữa ([workers.dev](https://developers.cloudflare.com/workers/configuration/routing/workers-dev/)). Điều này quan trọng cho việc bảo vệ web upload: các rule WAF và cấu hình Access trong [web-upload.vi.md](web-upload.vi.md) áp dụng cho tên miền riêng của bạn, không áp dụng cho `*.workers.dev`.

### Triển khai lại và cập nhật

- Mỗi lần push lên `main` sẽ triển khai lại. Bạn cũng có thể chạy lại workflow ở tab **Actions** (ví dụ sau khi đổi Secret hoặc Variable — thay đổi chỉ có hiệu lực ở lần chạy kế tiếp).
- Để kéo bản cập nhật của template về fork, dùng **Sync fork** trên GitHub.
- Migration D1 được áp dụng ở mỗi lần chạy; migration đã áp dụng sẽ được bỏ qua.
- Giữ nguyên `database_id = ""` trong `wrangler.toml` khi commit; CI tự điền trong workspace của nó.
- Xoá một Secret tuỳ chọn (ví dụ `VPS_URL` hoặc `SSE_MASTER_KEY`) khỏi GitHub **không** xoá nó khỏi Worker: các lần deploy giữ nguyên secret đã lưu trên Worker. Hãy xoá cả trên Worker bằng `npx wrangler secret delete <NAME> --name tg-s3-self`.

### Khắc phục sự cố (cách A)

| Triệu chứng / thông báo | Nguyên nhân và cách xử lý |
|-------------------------|---------------------------|
| Job hiển thị **skipped** | Variable `DEPLOY_ENABLED` chưa có hoặc không đúng chính xác `true` (đây là **Variable**, không phải Secret) |
| `Missing required repository secret: <NAME>` | Thêm Secret đó (bước 4). Tên Secret phân biệt chữ hoa/thường |
| `Variable CUSTOM_DOMAIN must be a bare hostname like files.example.com (no https://, no path)` | Chỉ đặt `CUSTOM_DOMAIN` là hostname, ví dụ `files.example.com` — không có scheme, không có path, không có dấu `/` ở cuối |
| `You need to register a workers.dev subdomain before publishing to workers.dev` | Làm một lần: dashboard → **Workers & Pages** → đặt **Your subdomain** (bước 2). Không cần nếu dùng `CUSTOM_DOMAIN` |
| `Authentication error [code: 10000]` hoặc lỗi quyền khác từ wrangler | API token thiếu quyền ở bước 3, bị giới hạn vào tài khoản/zone khác, hoặc `CLOUDFLARE_ACCOUNT_ID` thuộc tài khoản khác |
| `wrangler d1 list failed (check CLOUDFLARE_ACCOUNT_ID and that the API token has D1: Edit)` | `CLOUDFLARE_ACCOUNT_ID` sai, hoặc token thiếu **D1: Edit** / bị giới hạn vào tài khoản khác. Output của wrangler được in ngay phía trên dòng lỗi |
| `Could not find or create D1 database tg-s3-self-db` | Liệt kê được nhưng `wrangler d1 create` thất bại hoặc database mới không xuất hiện. Output của wrangler được in ngay phía trên dòng lỗi |
| `Could not create R2 bucket tg-s3-self-cache` | Token thiếu **Workers R2 Storage: Edit**, hoặc tài khoản chưa kích hoạt R2 (xem [Chuẩn bị](#chuẩn-bị)). Output của wrangler được in ngay phía trên dòng lỗi |
| `Could not find the workers.dev URL in the deploy output` | Lần deploy không xuất bản lên `workers.dev` (thường do chưa đăng ký subdomain workers.dev). Hãy đăng ký, hoặc đặt `CUSTOM_DOMAIN` |
| `setWebhook failed: <description>` | Telegram từ chối webhook; phần `description` cho biết lý do. Kiểm tra `TG_BOT_TOKEN` có đúng không và URL Worker có truy cập được qua HTTPS không (tên miền riêng mới tạo có thể cần vài phút — chạy lại workflow) |
| `Could not reach api.telegram.org` | Lỗi mạng từ runner; chạy lại job |
| Lỗi tên miền riêng khi deploy | Zone không cùng tài khoản, hoặc token thiếu quyền Zone |
| Bot không trả lời | Nhắn với bot trong **chat riêng**; kiểm tra user ID của bạn có trong `TG_ADMIN_IDS`; kiểm tra `getWebhookInfo` (xem [Kiểm tra sau triển khai](#kiểm-tra-sau-triển-khai)) |

## Cách B: `deploy.sh`

`deploy.sh` đọc `.env`, tìm hoặc tạo cơ sở dữ liệu D1 và bucket R2, áp dụng migration, tải secrets lên, triển khai Worker và đăng ký webhook Telegram. Tuỳ cách chạy, script còn build và chạy VPS processor bằng Docker.

### 1. Lấy mã nguồn và tạo `.env`

```bash
git clone https://github.com/<your-github-user>/tg-s3-cloudflare-self.git
cd tg-s3-cloudflare-self
cp .env.example .env
```

Sửa `.env`. Bắt buộc:

```bash
TG_BOT_TOKEN=123456:ABC-DEF...
DEFAULT_CHAT_ID=-1001234567890
TG_ADMIN_IDS=123456789
```

Khuyến nghị / tuỳ chế độ:

```bash
CLOUDFLARE_API_TOKEN=...          # bắt buộc ở chế độ Docker; nếu không sẽ dùng `wrangler login`
CLOUDFLARE_ACCOUNT_ID=...         # cần khi token thấy được nhiều tài khoản
CF_CUSTOM_DOMAIN=files.example.com  # tuỳ chọn, xem "Tên miền riêng và tunnel" bên dưới
TELEGRAM_API_ID=...               # tuỳ chọn, Local Bot API (file 2 GB)
TELEGRAM_API_HASH=...
```

Nếu thiếu `TG_BOT_TOKEN`, `DEFAULT_CHAT_ID` hoặc `TG_ADMIN_IDS` và bạn chạy script trong terminal tương tác, script sẽ hỏi và lưu câu trả lời vào `.env`. `VPS_SECRET` và `SSE_MASTER_KEY` được sinh tự động và ghi vào `.env` — hãy sao lưu `.env`, vì object mã hoá SSE-S3 sẽ không đọc được nếu thiếu đúng `SSE_MASTER_KEY` đó.

Mọi biến được mô tả trong [configuration.vi.md](configuration.vi.md).

### 2. Chọn chế độ

Script tự chọn chế độ:

| Lệnh | Điều kiện | Script làm gì |
|------|-----------|---------------|
| `./deploy.sh` | Có Docker và `docker compose` | **Máy chủ + Docker**: bắt buộc `CLOUDFLARE_API_TOKEN`; build image `deploy` và `processor`; triển khai Worker từ container `deploy` (và tạo Cloudflare Tunnel nếu đã cấu hình); khởi động `processor` (+ `tunnel`, + `telegram-bot-api` khi được bật) |
| `./deploy.sh` | Không có Docker | **Máy chủ không Docker**: chỉ triển khai Worker bằng wrangler trên máy (`npm install` nếu cần; nếu không có `CLOUDFLARE_API_TOKEN`, `wrangler login` sẽ mở trình duyệt). Không có processor, không có tunnel |
| `./deploy.sh --vps` | — | Triển khai Worker bằng wrangler trên máy, rồi triển khai processor lên server từ xa qua SSH (`VPS_SSH`, ví dụ `root@your-server`): cài Docker nếu chưa có, chép `processor/` và `docker-compose.yml` bằng `rsync` vào `VPS_DEPLOY_DIR` (mặc định `/opt/tg-s3-self`), ghi một file `.env` ở đó rồi chạy `docker compose up -d` |

Ở mọi chế độ, phần Worker gồm:

1. Tìm hoặc tạo D1 `tg-s3-self-db` (ID lấy từ `wrangler.toml`, rồi `D1_DATABASE_ID` trong `.env`, rồi từ tài khoản; lưu lại thành `D1_DATABASE_ID` trong `.env`).
2. Tạo R2 `tg-s3-self-cache` kèm rule lifecycle 90 ngày.
3. Áp dụng migration D1 (`--remote`).
4. Tải secrets: `TG_BOT_TOKEN`, `DEFAULT_CHAT_ID`, `VPS_SECRET`, cùng `VPS_URL`, `SSE_MASTER_KEY`, `TG_ADMIN_IDS` nếu có.
5. `wrangler deploy`.
6. Đặt secret `WORKER_URL` thành `https://<CF_CUSTOM_DOMAIN>` nếu có, nếu không thì dùng URL `*.workers.dev` từ output của lệnh deploy.
7. Đăng ký webhook Telegram tại `<WORKER_URL>/bot/webhook` (nếu thất bại chỉ in cảnh báo, không dừng script).

> [!NOTE]
> Ở chế độ không Docker và `--vps`, script ghi D1 ID vào `wrangler.toml` trên máy bạn. Nếu bạn cũng triển khai bằng GitHub Actions, đừng commit thay đổi này — giữ `database_id = ""` trong repository.

Secret mà sau này bạn xoá khỏi `.env` (ví dụ `VPS_URL`) vẫn còn trên Worker; hãy xoá bằng `npx wrangler secret delete <NAME> --name tg-s3-self`.

### Web upload khi dùng `deploy.sh`

`deploy.sh` **không** truyền `WEB_UPLOAD_BUCKET` từ `.env`. Muốn đổi bucket hoặc tắt web upload, sửa `wrangler.toml` trước khi chạy script:

```toml
[vars]
WEB_UPLOAD_BUCKET = "off"   # hoặc tên bucket khác; mặc định "files" = BẬT
```

Xem [web-upload.vi.md](web-upload.vi.md).

### Tên miền riêng và tunnel

`CF_CUSTOM_DOMAIN` chỉ được dùng cho hai việc:

- `WORKER_URL` và URL webhook trở thành `https://<CF_CUSTOM_DOMAIN>`.
- Ở chế độ Docker, script tạo Cloudflare Tunnel tên `tg-s3-self` với hostname `vps.<CF_CUSTOM_DOMAIN>` → `http://processor:3000`, tạo bản ghi DNS CNAME có proxy (nếu tìm thấy zone trong tài khoản), rồi ghi `CF_TUNNEL_TOKEN` và `VPS_URL=https://vps.<CF_CUSTOM_DOMAIN>` vào `.env`. Khi đó token cần thêm **Account → Cloudflare Tunnel: Edit** và **Zone → DNS: Edit**.

`deploy.sh` **không** gắn tên miền vào Worker. Trước khi chạy với `CF_CUSTOM_DOMAIN`, hãy tự thêm route và tắt URL `*.workers.dev` trong `wrangler.toml` ([Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/), [workers.dev](https://developers.cloudflare.com/workers/configuration/routing/workers-dev/)):

```toml
workers_dev = false

[[routes]]
pattern = "files.example.com"
custom_domain = true
```

Khi đó API token cần thêm **Zone → Workers Routes: Edit** và **Zone → DNS: Edit** trên zone đó. Nếu thiếu route, webhook sẽ trỏ tới một hostname không phục vụ Worker; `deploy.sh` in cảnh báo khi `CF_CUSTOM_DOMAIN` được đặt nhưng `wrangler.toml` không có route `pattern = "<CF_CUSTOM_DOMAIN>"` tương ứng. Giống cách A, hãy dùng một hostname riêng chưa phục vụ thứ gì khác.

Tunnel thủ công (không dùng `CF_CUSTOM_DOMAIN`): trong Cloudflare dashboard vào **Networking → Tunnels → Create a tunnel**, sau đó ở tab **Routes** của tunnel thêm một **Published application** với hostname thuộc một zone của bạn, trỏ tới `http://processor:3000` ([Create a tunnel (dashboard)](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel/)). Đặt cả `CF_TUNNEL_TOKEN` (token của connector) và `VPS_URL=https://<hostname-đó>` trong `.env` rồi chạy lại `./deploy.sh`. Khi `CF_TUNNEL_TOKEN` đã có, script bỏ qua bước tạo tunnel và không đổi `VPS_URL`.

### File lớn (tới 2 GB) với Local Bot API

Bot API công khai giới hạn file ở 20 MB. Để lên tới 2 GB cần **cả hai** điều kiện:

1. `TELEGRAM_API_ID` và `TELEGRAM_API_HASH` trong `.env` (lấy từ [my.telegram.org](https://my.telegram.org) → **API development tools** → tạo application). Khi đó script khởi động container `telegram-bot-api` và trỏ processor tới nó (`TG_LOCAL_API`).
2. Processor mà Worker truy cập được: `VPS_URL` là URL HTTPS công khai của processor (tự động khi dùng `CF_CUSTOM_DOMAIN` + tunnel ở chế độ Docker, hoặc tự đặt `CF_TUNNEL_TOKEN` + `VPS_URL`).

Nếu chỉ đặt một trong hai giá trị API, script sẽ cảnh báo và giữ giới hạn 20 MB.

> [!NOTE]
> `docker-compose.yml` không mở cổng processor ra máy chủ; processor được truy cập qua container tunnel. Ở chế độ `--vps`, file `.env` trên server không có `CF_TUNNEL_TOKEN` và dịch vụ tunnel không được khởi động, nên bạn phải tự đưa processor ra ngoài (reverse proxy hoặc tunnel riêng) và đặt `VPS_URL` tương ứng.

### Cập nhật

```bash
git pull
./deploy.sh          # hoặc ./deploy.sh --vps
```

Lệnh Docker hữu ích: `docker compose --profile tunnel logs -f`, `docker compose --profile tunnel restart`, `docker compose --profile tunnel down`.

### Khắc phục sự cố (cách B)

| Triệu chứng | Cách xử lý |
|-------------|------------|
| Script dừng vì thiếu `.env` | `cp .env.example .env` rồi điền giá trị |
| Thiếu giá trị bắt buộc (`TG_BOT_TOKEN`, `DEFAULT_CHAT_ID`, `TG_ADMIN_IDS`) | Điền vào `.env`, hoặc chạy `./deploy.sh` trong terminal tương tác để được hỏi |
| Chế độ Docker dừng và yêu cầu `CLOUDFLARE_API_TOKEN` | Chế độ Docker không dùng được `wrangler login`; thêm token vào `.env` |
| Không lấy được ID cơ sở dữ liệu D1 | Token thiếu **D1: Edit**, hoặc đặt `D1_DATABASE_ID` trong `.env` bằng ID của một database đã có |
| Cảnh báo đăng ký webhook, hoặc cảnh báo `CF_CUSTOM_DOMAIN=… has no [[routes]] entry in wrangler.toml` | Xem phản hồi Telegram được in ra; nếu dùng `CF_CUSTOM_DOMAIN`, thêm mục `[[routes]]` với `pattern = "<CF_CUSTOM_DOMAIN>"` và `custom_domain = true` vào `wrangler.toml` ([Tên miền riêng và tunnel](#tên-miền-riêng-và-tunnel)) rồi chạy lại |
| Không tạo được tunnel / processor "không truy cập được từ bên ngoài" | Đặt `CF_CUSTOM_DOMAIN`, thêm quyền **Cloudflare Tunnel: Edit** và **DNS: Edit** cho token rồi chạy lại; hoặc tự đặt `CF_TUNNEL_TOKEN` + `VPS_URL` |
| Processor gặp lỗi | `docker compose logs processor` (với `--vps`, trên server: `ssh <VPS_SSH> 'cd /opt/tg-s3-self && docker compose logs'`) |
| Lỗi SSH ở chế độ `--vps` | SSH bằng key phải chạy được không cần tương tác: `ssh -o BatchMode=yes <VPS_SSH> echo ok` |

## Phát triển local

```bash
npm install
npx wrangler d1 migrations apply tg-s3-self-db --local
```

Tạo file `.dev.vars` (đã có trong `.gitignore`) với tối thiểu:

```bash
TG_BOT_TOKEN=123456:ABC-DEF...
DEFAULT_CHAT_ID=-1001234567890
```

Chạy dev server:

```bash
X_LOCAL_EXPLORER=false npx wrangler dev
```

Cần `X_LOCAL_EXPLORER=false` vì `database_id` trong `wrangler.toml` đang để trống; với wrangler 4.90, lệnh `wrangler dev` thông thường sẽ crash với lỗi *"The expression evaluated to a falsy value: (databaseId)"*.

Kiểm tra kiểu bằng `npm run typecheck`.

## Kiểm tra sau triển khai

```bash
# Trạng thái webhook (phải hiện <WORKER_URL>/bot/webhook và không có last_error_message)
curl "https://api.telegram.org/bot<TG_BOT_TOKEN>/getWebhookInfo"

# S3 API (tạo thông tin đăng nhập trước trong Mini App → tab Keys)
aws --endpoint-url https://files.example.com s3 ls
aws --endpoint-url https://files.example.com s3 mb s3://test
aws --endpoint-url https://files.example.com s3 cp file.txt s3://test/

# rclone
rclone config create tgs3 s3 provider=Other \
  access_key_id=YOUR_KEY secret_access_key=YOUR_SECRET \
  endpoint=https://files.example.com acl=private
rclone ls tgs3:test
```

Thay `https://files.example.com` bằng URL Worker của bạn. Xem log trực tiếp: `npx wrangler tail tg-s3-self`. Chi tiết tương thích S3 (tiếng Anh): [S3-COMPAT.md](S3-COMPAT.md).
