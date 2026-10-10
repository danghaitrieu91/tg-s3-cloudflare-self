# Tham chiếu cấu hình

[English](configuration.md) | **Tiếng Việt**

Mỗi giá trị được đặt ở đâu phụ thuộc vào cách triển khai (xem [deployment.vi.md](deployment.vi.md)):

| Nơi đặt | Dùng cho | Cách đặt |
|---------|----------|----------|
| **GitHub Secret** | Cách A (GitHub Actions) | Fork → Settings → Secrets and variables → Actions → Secrets |
| **GitHub Variable** | Cách A (GitHub Actions) | Cùng trang → Variables |
| **`.env`** | Cách B (`deploy.sh`, Docker) | `cp .env.example .env`; được `deploy.sh` và `docker-compose.yml` đọc |
| **`wrangler.toml`** | Cả hai cách | `[vars]`, binding, cron; được commit trong repository |
| **`.dev.vars`** | Phát triển local (`wrangler dev`) | File ở thư mục gốc, đã có trong `.gitignore` |

Các **secret** của Worker (`TG_BOT_TOKEN`, `DEFAULT_CHAT_ID`, `TG_ADMIN_IDS`, `WORKER_URL`, `SSE_MASTER_KEY`, `VPS_URL`, `VPS_SECRET`) được workflow hoặc `deploy.sh` tải lên Cloudflare. Chúng không bao giờ được ghi vào `wrangler.toml`.

## Cài đặt của Worker

Đây là các trường của interface `Env` trong `src/types.ts` cùng với `WEB_UPLOAD_BUCKET`.

| Tên | Bắt buộc | Mục đích | Cách A | Cách B |
|-----|----------|----------|--------|--------|
| `TG_BOT_TOKEN` | Có | Bot token Telegram từ @BotFather. Cũng dùng để suy ra webhook secret | Secret | `.env` |
| `DEFAULT_CHAT_ID` | Có | Chat ID của supergroup (`-100…`) nơi lưu file. Bot phải là admin trong nhóm | Secret | `.env` |
| `TG_ADMIN_IDS` | Có (CI và `deploy.sh` bắt buộc) | Danh sách user ID Telegram được dùng bot **và** API của Mini App (xác thực initData / Bearer), cách nhau bằng dấu phẩy, ví dụ `123456789,987654321`. Nếu Worker chạy mà thiếu biến này, **bất kỳ** người dùng Telegram nào cũng dùng được bot, và bất kỳ ai mở Mini App cũng được chấp nhận. Những người dùng này cũng nhận [cảnh báo từ cron](#tác-vụ-bảo-trì-định-kỳ-cron) và tin nhắn báo sao lưu thất bại; mỗi người phải gửi `/start` cho bot một lần, nếu không Telegram sẽ từ chối gửi tin | Secret | `.env` |
| `WORKER_URL` | Tự động | URL công khai của Worker (có dấu `/` ở cuối cũng được). Dùng cho link chia sẻ bot gửi ra, để xoá cache CDN trong cron, để webhook tự phục hồi (cron đăng ký lại `<WORKER_URL>/bot/webhook` khi webhook bị mất) và làm host đối chiếu cho cảnh báo của cron. Nếu thiếu, cron không sửa được webhook mà chỉ gửi cảnh báo. Không tự đặt | CI đặt (`https://<CUSTOM_DOMAIN>` hoặc URL `*.workers.dev`) | `deploy.sh` đặt (`https://<CF_CUSTOM_DOMAIN>` hoặc URL `*.workers.dev`) |
| `SSE_MASTER_KEY` | Không | Khoá base64 32 byte cho SSE-S3 (mã hoá do server quản lý). Tạo bằng `openssl rand -base64 32`. Không có khoá thì yêu cầu SSE-S3 bị từ chối. Giữ khoá vĩnh viễn: object đã mã hoá sẽ không đọc được nếu mất khoá | Secret (tuỳ chọn) | Tự sinh vào `.env` |
| `VPS_URL` | Không | URL HTTPS công khai của VPS processor (file > 20 MB, xử lý media) | Secret (tuỳ chọn) | `.env`; tự đặt khi `deploy.sh` tạo tunnel |
| `VPS_SECRET` | Không | Khoá bí mật dùng chung giữa Worker và processor (processor đọc nó dưới tên `AUTH_SECRET`) | Secret (tuỳ chọn; phải khớp với processor) | Tự sinh vào `.env` |
| `S3_REGION` | Có (có mặc định) | Region mà S3 API báo về | `wrangler.toml` `[vars]`, mặc định `us-east-1` | như trên |
| `WEB_UPLOAD_BUCKET` | Không (mặc định `files`) | Bucket cho trang web upload công khai. `off` (không phân biệt hoa/thường) hoặc để trống sẽ tắt trang và `POST /api/web-upload`. Giá trị khác phải là tên bucket hợp lệ (`^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$` sau khi chuyển chữ thường), nếu không mọi lần tải lên đều lỗi `500`. Xem [web-upload.vi.md](web-upload.vi.md) | Variable; không đặt = giá trị trong `wrangler.toml` (`files`) | Chỉ `wrangler.toml` `[vars]` — **`deploy.sh` bỏ qua `WEB_UPLOAD_BUCKET` trong `.env`** |
| `DB` | Có (binding) | Cơ sở dữ liệu D1 `tg-s3-self-db` (metadata) | `wrangler.toml` `[[d1_databases]]`; CI điền `database_id` | như trên; `deploy.sh` điền `database_id` |
| `CACHE` | Không (binding) | Bucket R2 `tg-s3-self-cache` (cache file nóng, file ≤ 20 MB) | `wrangler.toml` `[[r2_buckets]]`; CI tạo bucket | như trên; `deploy.sh` tạo kèm rule lifecycle 90 ngày |
| `WEB_UPLOAD_LIMITER` | Không (binding) | Binding Workers Rate Limiting cho `POST /api/web-upload`: 30 request mỗi 60 giây cho mỗi client (địa chỉ IPv4 hoặc dải IPv6 /64). Chỉ để làm chậm; nếu chính bộ giới hạn bị lỗi thì lượt tải lên vẫn được cho qua (fail open). Xem [web-upload.vi.md → Giới hạn tốc độ tích hợp](web-upload.vi.md#giới-hạn-tốc-độ-tích-hợp) | `wrangler.toml` `[[ratelimits]]` | như trên |

Để biết user ID Telegram của bạn, gửi một tin nhắn bất kỳ cho [@userinfobot](https://t.me/userinfobot).

## Chỉ dùng cho GitHub Actions

| Tên | Loại | Bắt buộc | Mục đích |
|-----|------|----------|----------|
| `CLOUDFLARE_API_TOKEN` | Secret | Có | API token cho wrangler. Quyền cần có: [deployment.vi.md → Tạo Cloudflare API token](deployment.vi.md#3-tạo-cloudflare-api-token) |
| `CLOUDFLARE_ACCOUNT_ID` | Secret | Có | Account ID Cloudflare |
| `DEPLOY_ENABLED` | Variable | Có | Phải đúng chính xác `true`; nếu không, job deploy bị bỏ qua |
| `CUSTOM_DOMAIN` | Variable | Không | Hostname trần thuộc một zone trên cùng tài khoản Cloudflare, ví dụ `files.example.com` (không có `https://`, không có path). CI thêm route Custom Domain và đặt `workers_dev = false` (chỉ trong workspace của CI). Hãy dùng một hostname riêng, chưa dùng: bản ghi DNS hoặc Custom Domain đang có trên hostname đó sẽ bị trỏ sang Worker này ([deployment.vi.md](deployment.vi.md#tên-miền-riêng)) |
| `WEB_UPLOAD_BUCKET` | Variable | Không | Ghi đè `wrangler.toml` khi deploy (`--var`). Xem [Cài đặt của Worker](#cài-đặt-của-worker) |

### Workflow sao lưu

`.github/workflows/backup.yml` chạy hằng ngày lúc 03:17 UTC và khi chạy tay, chỉ khi `DEPLOY_ENABLED` là `true` (job tối đa 20 phút). Workflow dùng chung các Secret với workflow deploy (`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `TG_BOT_TOKEN`, `TG_ADMIN_IDS`) và không cần cấu hình thêm. Nó xuất D1 bằng `scripts/d1-backup.sh` vào bucket R2 `tg-s3-self-backup` (được tạo ở lần chạy đầu):

| Key | Nội dung |
|-----|----------|
| `d1/<Mon..Sun>.sql` | Bản sao xoay vòng 7 ngày (mỗi thứ trong tuần một bản, bị ghi đè sau một tuần) |
| `d1/monthly/<YYYY-MM>.sql` | Bản sao theo tháng (lần chạy cuối cùng trong tháng) |
| `d1/last-count.json` | Số object và bucket của lần sao lưu tốt gần nhất, dùng cho cơ chế chặn khi dữ liệu bị hụt |

Mỗi bản sao là một lần `wrangler d1 export` đầy đủ (schema và dữ liệu của mọi bảng, kể cả `d1_migrations`) đã bỏ các dòng của bảng `credentials` (S3 secret không được sao lưu). Bảng mới được tự động đưa vào. Trước khi tải lên, bản dump được khôi phục thử vào một D1 cục bộ tạm trên runner; số liệu trong `d1/last-count.json` lấy từ lần khôi phục thử đó. Cơ chế chặn, khôi phục và xử lý lỗi: [deployment.vi.md → Sao lưu và khôi phục](deployment.vi.md#sao-lưu-và-khôi-phục).

## Chỉ dùng cho `deploy.sh` / `.env`

| Tên | Bắt buộc | Mục đích |
|-----|----------|----------|
| `CLOUDFLARE_API_TOKEN` | Chế độ Docker: có; còn lại: không | API token cho wrangler. Nếu không có (chế độ không Docker) sẽ dùng `wrangler login`. Quyền giống cách A, thêm **Cloudflare Tunnel: Edit** và **DNS: Edit** để tự tạo tunnel |
| `CLOUDFLARE_ACCOUNT_ID` | Không | Cần khi token truy cập được nhiều tài khoản. Tên cũ `CF_ACCOUNT_ID` vẫn được chấp nhận |
| `CF_CUSTOM_DOMAIN` | Không | Đặt `WORKER_URL`/webhook thành `https://<domain>` và, ở chế độ Docker, tạo hostname tunnel `vps.<domain>`. Biến này **không** gắn tên miền vào Worker: hãy tự thêm `[[routes]]` và `workers_dev = false` vào `wrangler.toml` ([deployment.vi.md](deployment.vi.md#tên-miền-riêng-và-tunnel)) |
| `CF_TUNNEL_TOKEN` | Không | Token connector của Cloudflare Tunnel. Tự ghi khi script tạo tunnel; tự đặt nếu bạn tạo tunnel thủ công (khi đó đặt luôn `VPS_URL`) |
| `TELEGRAM_API_ID`, `TELEGRAM_API_HASH` | Không | Bật container Local Bot API (file tới 2 GB). Cần cả hai. Lấy tại [my.telegram.org](https://my.telegram.org) → **API development tools** |
| `TG_LOCAL_API` | Tự động | Endpoint Bot API mà processor dùng. Là `http://telegram-bot-api:8081` khi bật Local Bot API, ngược lại là `https://api.telegram.org` |
| `D1_DATABASE_ID` | Tự động | ID cơ sở dữ liệu D1 được ghi nhớ sau lần deploy đầu (container deploy của Docker không lưu được `wrangler.toml`) |
| `VPS_SECRET`, `SSE_MASTER_KEY` | Tự động | Sinh ở lần chạy đầu nếu đang trống, xem [Cài đặt của Worker](#cài-đặt-của-worker) |
| `VPS_SSH` | Chỉ `--vps` | Đích SSH của server chạy processor, ví dụ `root@your-server` (phải đăng nhập bằng key) |
| `VPS_DEPLOY_DIR` | Không | Thư mục trên server cho `--vps`, mặc định `/opt/tg-s3-self` |
| `VPS_PORT` | Không | Cổng dùng cho bước kiểm tra sức khoẻ của `--vps` (mặc định `3000`). `docker-compose.yml` chạy processor ở cổng 3000 |

**Lấy `TELEGRAM_API_ID` và `TELEGRAM_API_HASH`:**

1. Vào [my.telegram.org](https://my.telegram.org) và đăng nhập bằng số điện thoại.
2. Bấm **API development tools**.
3. Tạo application (các trường chỉ là thông tin mô tả): **App title** tuỳ ý (ví dụ `tg-s3`), **Short name** gồm 5–32 ký tự chữ và số, **Platform** chọn `Other`, để trống URL và mô tả.
4. Sao chép `api_id` (số) và `api_hash` (chuỗi) vào `.env`.

## Phát triển local

Tạo `.dev.vars` với tối thiểu `TG_BOT_TOKEN` và `DEFAULT_CHAT_ID` (có thể thêm bất kỳ cài đặt Worker nào ở trên). Các `[vars]` trong `wrangler.toml` cũng được áp dụng. Chạy `X_LOCAL_EXPLORER=false npx wrangler dev`; xem [deployment.vi.md → Phát triển local](deployment.vi.md#phát-triển-local).

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

[[ratelimits]]
name = "WEB_UPLOAD_LIMITER"
namespace_id = "73201"
simple = { limit = 30, period = 60 }

[observability]
enabled = true

[observability.logs]
invocation_logs = false
```

- Giữ `database_id = ""` trong repository; CI tự điền trong workspace của nó. Không bao giờ đặt comment trên dòng `database_id`: `deploy.sh` đọc (parse) chính dòng đó.
- Mặc định không có mục `[[routes]]`. Cách A tự thêm khi đặt `CUSTOM_DOMAIN`; với cách B hãy tự thêm (xem [deployment.vi.md](deployment.vi.md#tên-miền-riêng-và-tunnel)).
- Schema được quản lý bằng các file SQL trong `migrations/` (`wrangler d1 migrations apply`).
- `[[ratelimits]]` đặt giới hạn cho web upload; sửa `limit` (và `period`, chỉ nhận `10` hoặc `60`) rồi deploy lại. `namespace_id` có phạm vi toàn tài khoản: hãy giữ giá trị này không trùng giữa các Worker của bạn để chúng không dùng chung bộ đếm. Xem [web-upload.vi.md](web-upload.vi.md#giới-hạn-tốc-độ-tích-hợp).
- `[observability]` bật Workers Logs, nên output `console.*` (kết quả cron, lỗi) được lưu lại và tìm kiếm được trong dashboard. `invocation_logs = false` để Cloudflare không lưu log cho từng request, vì URL của request có thể chứa token `auth=` của Mini App và mật khẩu link chia sẻ. Dùng `npx wrangler tail tg-s3-self` khi cần xem request trực tiếp để gỡ lỗi.

### Tác vụ bảo trì định kỳ (cron)

Trình xử lý định kỳ chạy mỗi 6 giờ và:

1. Kiểm tra webhook Telegram: nếu bị mất thì đăng ký lại tại `<WORKER_URL>/bot/webhook`; nếu trỏ sang host khác hoặc có báo lỗi trong 6 giờ qua thì gửi cảnh báo (không thay đổi gì); nếu chưa có `WORKER_URL` thì gửi cảnh báo.
2. Kiểm tra khả năng truy cập file trên Telegram (chỉ báo cáo): gọi `getFile` cho một mẫu ~2% số object, giới hạn 5–12 object mỗi lần chạy, chỉ object ≤ 20 MB, trong tối đa 120 giây. Bước này **không bao giờ xoá** gì. File mà Telegram báo không còn, token sai hoặc bị thu hồi, token thuộc về một bot khác, hoặc Telegram đang trục trặc đều được báo thành cảnh báo.
3. Gửi các cảnh báo từ bước 1–2 thành tin nhắn Telegram tới mọi người dùng trong `TG_ADMIN_IDS`. Nếu có cảnh báo mà không gửi được cho ai, lần chạy kết thúc với lỗi `cron alerts undelivered` (xem trong dashboard, mục Cron Events của Worker).
4. Dọn các share token đã hết hạn.
5. Dọn các share token mồ côi (object đã xoá nhưng share còn).
6. Dọn các multipart upload bị bỏ dở (> 24 giờ).
7. Dọn các chunk mồ côi.
8. Dọn các bản ghi thử mật khẩu đã hết hạn.
9. Dọn cache R2 (loại bỏ object đã bị xoá khỏi D1).
10. Áp dụng rule lifecycle của bucket (xoá object hết hạn).

## Lưu ý bảo mật

- **Thông tin đăng nhập S3** được lưu trong D1 và dùng để xác thực AWS SigV4. Tạo, thu hồi và giới hạn theo từng bucket trong tab **Keys** của Mini App.
- **Webhook secret** được suy ra từ `TG_BOT_TOKEN` (HMAC-SHA256 của chuỗi `tg-s3-webhook`); không có biến riêng. Đổi bot token thì phải đăng ký lại webhook (triển khai lại).
- **`TG_ADMIN_IDS`** giới hạn ai được điều khiển bot và ai được dùng API của Mini App. CI và `deploy.sh` từ chối triển khai nếu thiếu biến này.
- **Web upload** là công khai và được bật sẵn; hãy đọc [web-upload.vi.md](web-upload.vi.md).
- **`CLOUDFLARE_API_TOKEN`** có quyền thay đổi tài khoản Cloudflare của bạn. Chỉ lưu trong GitHub Secrets hoặc `.env`, không bao giờ đưa vào repository. `.env` và `.dev.vars` đã có trong `.gitignore`.

## Giới hạn

| Tài nguyên | Giới hạn |
|------------|----------|
| Web upload / tải lên qua Mini App | 20 MB mỗi file |
| Truyền file qua Telegram Bot API | 20 MB (Bot API công khai) / 2 GB (Local Bot API qua processor) |
| Cache R2 | Chỉ cache file ≤ 20 MB |

Giới hạn theo gói của Cloudflare (số request, truy vấn D1, thao tác R2) thay đổi theo thời gian; hãy xem tài liệu hiện hành của Cloudflare về giới hạn Workers, D1 và R2 cho gói bạn dùng.
