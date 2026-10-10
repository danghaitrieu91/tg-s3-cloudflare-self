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
5. Chỉ cho cách B / phát triển local: **Node.js 22.18+** (dự án dùng wrangler v4; `npm test` cần tính năng tự lược bỏ kiểu TypeScript (type stripping) có sẵn trong Node).

## Cách A: GitHub Actions

Workflow nằm ở `.github/workflows/deploy.yml`. Nó chạy mỗi khi push lên `main` và khi chạy tay, nhưng job deploy sẽ bị **bỏ qua (skipped)** cho đến khi bạn đặt Variable `DEPLOY_ENABLED` của repo thành `true`. Một job `test` riêng (kiểm tra kiểu và unit test, không dùng secret nào) chạy trước ở mọi lần push và mọi pull request, kể cả trên fork; job deploy chỉ bắt đầu khi job này thành công và không bao giờ chạy cho pull request.

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
| Test (job `test`) | `npm ci`, `npm run typecheck`, `npm test`. Chạy khi push và khi có pull request, không cần secret; nếu lỗi thì không deploy |
| Validate required secrets | Báo lỗi `Missing required repository secret: <NAME>` nếu một trong các secret `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `TG_BOT_TOKEN`, `DEFAULT_CHAT_ID`, `TG_ADMIN_IDS` bị trống, và báo `Variable CUSTOM_DOMAIN must be a bare hostname …` nếu `CUSTOM_DOMAIN` không phải hostname trần |
| Ensure D1 database | Tìm `tg-s3-self-db` (`wrangler d1 list --json`), tạo mới nếu chưa có, rồi ghi ID vào `wrangler.toml` **chỉ trong workspace của CI** (không bao giờ commit). Báo lỗi `wrangler d1 list failed …` nếu chính bước tìm kiếm thất bại |
| Ensure R2 cache bucket | Tạo `tg-s3-self-cache`; lỗi "already exists" được coi là thành công |
| Configure custom domain | Chỉ khi có `CUSTOM_DOMAIN`: thêm `[[routes]] pattern = "<domain>" custom_domain = true` và đặt `workers_dev = false` (chỉ trong workspace) |
| D1 bookmark | In thông báo (notice) `D1 bookmark before migrations: <id>` trong phần tóm tắt của lần chạy: một điểm khôi phục D1 Time Travel được lấy trước khi chạy migration (xem [Sao lưu và khôi phục](#sao-lưu-và-khôi-phục)). Với database mới tinh thì chỉ là cảnh báo |
| Apply D1 migrations | `wrangler d1 migrations apply tg-s3-self-db --remote` |
| Deploy Worker | `wrangler deploy --secrets-file …`: secrets được tải lên cùng lúc với mã nguồn. Chỉ thêm `--var WEB_UPLOAD_BUCKET:<giá-trị>` khi Variable được đặt. In ra thông báo web upload đang BẬT hay TẮT |
| Resolve Worker URL | `https://<CUSTOM_DOMAIN>`, hoặc URL `*.workers.dev` lấy từ output của lệnh deploy, sau đó lưu thành secret `WORKER_URL` |
| Register Telegram webhook | Gọi `setWebhook` với `<WORKER_URL>/bot/webhook` và secret token suy ra từ bot token (HMAC-SHA256). Job thất bại nếu Telegram không trả về `ok` |
| Smoke test | Gửi request không xác thực tới `<WORKER_URL>/tgs3-smoke-nonexistent/x` (tối đa 12 lần, cách nhau 10 giây) và chờ mã `403` kèm body lỗi S3 của Worker `<Code>AccessDenied</Code>`, chứng tỏ phiên bản mới đọc được D1 và chạy qua bước xác thực S3. Mã `403` do lớp edge (WAF, Access) trả về không được tính. Mọi kết quả khác làm job thất bại |

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
- Pull request (kể cả từ fork) chỉ chạy job `test`; không có gì được deploy cho tới khi thay đổi vào `main`.

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
| `Smoke test failed (HTTP <code>, expected 403 AccessDenied from the Worker)` | Phiên bản mới **đã chạy thật** nhưng trả lời sai. `403-unexpected` là 403 không có body `AccessDenied` của Worker: một rule WAF hoặc Cloudflare Access đang chặn đường dẫn, hãy cho phép các đường dẫn S3. `500` thường là lỗi D1 hoặc migration; `000`, `404` hay `52x` thường là URL chưa phục vụ được (tên miền riêng mới có thể cần vài phút — chạy lại workflow). Xem `npx wrangler tail tg-s3-self`, rồi sửa và push, hoặc quay lại mã cũ bằng `npx wrangler rollback --name tg-s3-self`. Nếu migration làm hỏng dữ liệu, khôi phục D1 về bookmark mà chính lần chạy đó in ra ([Sao lưu và khôi phục](#sao-lưu-và-khôi-phục)) |
| D1 backup: `getMe failed: … (TG_BOT_TOKEN invalid or revoked?)` | Bản sao lưu đã chạy xong (bước kiểm tra này chạy sau khi tải lên, kể cả khi một bước trước đó lỗi), nhưng Telegram từ chối bot token, nên bot đã chết và cũng không gửi được cảnh báo. Nếu token bị thu hồi, lấy token mới từ @BotFather, cập nhật Secret `TG_BOT_TOKEN`, chạy lại **Deploy to Cloudflare Workers** (tải token lên và đăng ký lại webhook), rồi chạy lại **D1 backup** |
| D1 backup: `No Telegram webhook is set; …` | Bản sao lưu đã chạy xong, nhưng bot không nhận được tin nhắn. Lần chạy cron kế tiếp (mỗi 6 giờ) sẽ đăng ký lại webhook nếu có `WORKER_URL`; muốn sửa ngay thì chạy lại **Deploy to Cloudflare Workers** |
| D1 backup: `D1 database tg-s3-self-db not found; not creating it` | Job sao lưu không bao giờ tạo database, để không sao lưu một database trống thay thế đè lên bản sao lưu tốt. Kiểm tra `CLOUDFLARE_ACCOUNT_ID` có đúng tài khoản không. Nếu database thật sự đã mất, làm theo [Khôi phục khi database đã mất](#khôi-phục-khi-database-đã-mất) |
| D1 backup: `Could not read d1/last-count.json from tg-s3-self-backup; refusing to run without the shrink guard` | Đọc số liệu lần trước thất bại vì lý do khác với "key không tồn tại" (mạng, quyền). Job dừng lại thay vì chạy mà không có cơ chế chặn. Kiểm tra token có quyền **Workers R2 Storage: Edit**, rồi chạy lại **D1 backup** |
| D1 backup: `refusing to overwrite backups: objects N -> M` | Số object trong bản dump đã kiểm tra giảm về 0 hoặc dưới một nửa so với lần sao lưu tốt gần nhất. Không có gì được tải lên; các bản sao lưu cũ còn nguyên. Nếu điều này bất thường, hãy điều tra và khôi phục ([Sao lưu và khôi phục](#sao-lưu-và-khôi-phục)). Nếu bạn cố ý xoá các file đó, chấp nhận số mới như trong [Sao lưu hằng ngày](#sao-lưu-hằng-ngày-github-actions) |

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

Các image của bên thứ ba (`aiogram/telegram-bot-api`, `cloudflare/cloudflared`) không được ghim phiên bản và chỉ được tải về một lần: `deploy.sh` không bao giờ tải lại, nên chạy lại script không nâng cấp chúng. Hãy chủ động nâng cấp trong thư mục chứa `docker-compose.yml` (trên server nếu dùng `--vps`), rồi kiểm tra log sau đó:

```bash
docker compose pull && docker compose up -d
```

Các dịch vụ này nằm sau profile của Compose, nên hãy thêm các profile bạn đang chạy vào cả hai lệnh, ví dụ `docker compose --profile tunnel --profile localapi pull && docker compose --profile tunnel --profile localapi up -d`.

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

## Cảnh báo

Cron của Worker (mỗi 6 giờ, cả hai cách) gửi một tin nhắn Telegram có tiêu đề **tg-s3 cron** tới mọi người dùng trong `TG_ADMIN_IDS` khi có việc cần xử lý. Mỗi admin phải gửi `/start` cho bot một lần, nếu không Telegram sẽ từ chối gửi tin. Cron không bao giờ xoá object vì lỗi từ Telegram. Chi tiết từng bước: [configuration.vi.md → Tác vụ bảo trì định kỳ](configuration.vi.md#tác-vụ-bảo-trì-định-kỳ-cron).

| Cảnh báo | Ý nghĩa và cách xử lý |
|----------|-----------------------|
| `getFile 400 for N of M sampled (lost, or not readable by this bot). Nothing was deleted.` + tối đa 10 key | Telegram không còn phục vụ các file này (ví dụ tin nhắn đã bị xoá khỏi nhóm lưu trữ). Kiểm tra nhóm; nếu file thật sự mất, tự xoá các object được liệt kê (lệnh bot `/delete`, Mini App hoặc S3) |
| `All probes returned 400: TG_BOT_TOKEN is valid but probably belongs to a different bot …` | File ID chỉ dùng được với bot đã tải file lên. Có lẽ `TG_BOT_TOKEN` đã bị thay bằng token của bot khác: đặt lại token của bot ban đầu rồi deploy lại |
| `getFile returned 401 … TG_BOT_TOKEN invalid or revoked.` | Tạo token mới cho chính bot đó trong @BotFather, cập nhật Secret (hoặc `.env`) rồi deploy lại |
| `Telegram unreachable or degraded: …` | Ít nhất một nửa số lần kiểm tra lỗi tạm thời. Thường tự hết; chỉ cần xử lý nếu lặp lại |
| `Webhook was missing → re-registered.` | Chỉ để thông báo: webhook bị trống và cron đã đặt lại |
| `Webhook re-register FAILED …`, `Webhook: getWebhookInfo failed …` | Telegram từ chối hoặc không trả lời. Chạy lại deploy (workflow cách A hoặc `./deploy.sh`) |
| `Webhook points to another host (…); not changed.` | Một bản triển khai khác (hoặc một lệnh `setWebhook` thủ công) đã chiếm bot. Cron không giành lại; hãy deploy lại bản này nếu nó là bản phải sở hữu bot |
| `Webhook error: …` | Telegram báo lỗi gửi webhook trong 6 giờ qua. Kiểm tra URL Worker còn hoạt động, rồi xem [Kiểm tra sau triển khai](#kiểm-tra-sau-triển-khai) |
| `WORKER_URL not set: webhook self-heal disabled.` | Deploy lại để CI hoặc `deploy.sh` đặt `WORKER_URL` |

Nếu có cảnh báo mà không gửi được cho ai (chưa admin nào `/start` bot, hoặc token đã bị thu hồi), lần chạy cron kết thúc với lỗi `cron alerts undelivered`, xem được trong dashboard Cloudflare ở mục **Cron Events** của Worker. Token bị thu hồi thì không gửi được tin Telegram nào, nên với GitHub Actions, [job sao lưu hằng ngày](#sao-lưu-hằng-ngày-github-actions) là kênh dự phòng: sau khi sao lưu, nó kiểm tra token bằng `getMe` và thất bại, khiến GitHub gửi email báo workflow lỗi. Hãy giữ bật email thông báo của GitHub.

## Sao lưu và khôi phục

Có hai lớp bảo vệ metadata D1 (bản thân file vẫn nằm trên Telegram, nhưng thiếu D1 thì không tìm lại được):

| Lớp | Nội dung | Nơi lưu |
|-----|----------|---------|
| D1 Time Travel | Khôi phục về một thời điểm, có sẵn trong D1, chừng nào database còn tồn tại (thời gian lưu: 7 ngày với Workers Free, 30 ngày với Workers Paid) | Cloudflare |
| Bản xuất hằng ngày (chỉ cách A) | `.github/workflows/backup.yml`: mỗi ngày một bản SQL đầy đủ | Bucket R2 `tg-s3-self-backup` |

`deploy.sh` (cách B) không có sao lưu định kỳ; Time Travel vẫn áp dụng.

### Time Travel (lựa chọn đầu tiên)

Dùng khi database vẫn còn nhưng nội dung bị sai (migration lỗi, lỡ xoá hàng loạt). Mỗi lần deploy đều in ra một điểm khôi phục lấy trước khi chạy migration: mở phần tóm tắt của lần chạy **Deploy to Cloudflare Workers** và tìm thông báo `D1 bookmark before migrations: <id>`.

```bash
export CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ACCOUNT_ID=...
# khôi phục về bookmark mà một lần deploy đã in ra
npx wrangler d1 time-travel restore tg-s3-self-db --bookmark=<id>
# hoặc tìm bookmark của một thời điểm, rồi khôi phục về bookmark đó
npx wrangler d1 time-travel info tg-s3-self-db --timestamp=2026-10-09T12:00:00Z
```

Khôi phục sẽ thay toàn bộ database tại chỗ; wrangler in ra bookmark của trạng thái trước khi khôi phục, nên có thể hoàn tác theo cùng cách. Xem [D1 Time Travel](https://developers.cloudflare.com/d1/reference/time-travel/).

### Sao lưu hằng ngày (GitHub Actions)

- Chạy hằng ngày lúc 03:17 UTC và khi chạy tay (**Actions → D1 backup → Run workflow**), chỉ khi `DEPLOY_ENABLED` là `true`. Job tự dừng sau 20 phút.
- Job chỉ tìm `tg-s3-self-db` ở chế độ chỉ đọc và **không bao giờ tạo mới**: nếu database không còn, job thất bại với `D1 database tg-s3-self-db not found; not creating it`.
- Job xuất toàn bộ database bằng một lệnh `wrangler d1 export` (schema và dữ liệu của mọi bảng, kể cả `d1_migrations`, nên bảng mới được tự động đưa vào), rồi **kiểm tra** bản dump bằng cách khôi phục thử vào một D1 cục bộ tạm trên runner. Số liệu lưu trong `d1/last-count.json` lấy từ lần khôi phục thử đó.
- Job từ chối ghi đè bản sao lưu tốt (`refusing to overwrite backups: objects N -> M`) khi số object sau khi khôi phục thử giảm về 0 hoặc dưới 50% so với lần chạy tốt gần nhất. Lần chạy đầu tiên (chưa có `d1/last-count.json`) chấp nhận mọi con số. Chỉ khi key không tồn tại mới được coi là lần đầu: mọi lỗi khác khi đọc file đếm đều làm job dừng (`Could not read d1/last-count.json …`).
- Job tải lên `d1/<Mon..Sun>.sql` (xoay vòng 7 ngày) và `d1/monthly/<YYYY-MM>.sql`, rồi `d1/last-count.json` (bố cục: [configuration.vi.md → Workflow sao lưu](configuration.vi.md#workflow-sao-lưu)).
- Sau khi tải lên, job kiểm tra bot bằng `getMe` và kiểm tra webhook đã được đặt. Bước này chạy cả khi một bước trước đó lỗi, và bot hỏng không chặn việc sao lưu, nhưng vẫn làm job thất bại, nên GitHub vẫn gửi email báo lỗi kể cả khi Telegram không gửi được tin.
- **S3 credential không được sao lưu** (bản dump vẫn tạo bảng `credentials`, nhưng các dòng của nó đã bị bỏ). Sau khi khôi phục, hãy tạo key mới ở tab **Keys** của Mini App.
- Khi thất bại hoặc bị huỷ, mọi admin trong `TG_ADMIN_IDS` cũng nhận tin nhắn Telegram `tg-s3 daily D1 backup / bot health check failed: <run URL>` (nếu gửi được).
- **Chấp nhận một lần xoá lớn có chủ ý**: xoá file đếm, rồi chạy workflow bằng tay; lần chạy đó được coi như lần đầu.

  ```bash
  npx wrangler r2 object delete tg-s3-self-backup/d1/last-count.json --remote
  ```

- GitHub tạm dừng các workflow định kỳ trong repository không có hoạt động nào suốt 60 ngày. Nếu xảy ra, bật lại **D1 backup** trong tab **Actions** (hoặc push một commit); Time Travel vẫn hoạt động trong lúc đó.

### Khôi phục khi database đã mất

Chỉ dùng khi database đã bị xoá hoặc Time Travel không còn lùi đủ xa. Bản sao phải được khôi phục vào một database **trống**.

1. Đặt GitHub Variable `WEB_UPLOAD_BUCKET` thành `off` để trang công khai vẫn tắt cho tới khi bạn kiểm tra xong, và **không push lên `main` hay chạy workflow deploy** cho tới bước 6: khi thiếu database, workflow sẽ tạo database mới và chạy mọi migration, nên database không còn trống nữa.
2. Tạo một database trống và ghi lại ID:

   ```bash
   export CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ACCOUNT_ID=...
   npx wrangler d1 create tg-s3-self-db
   ```

   Điền ID mới vào `database_id` trong `wrangler.toml` trên máy bạn để chạy các lệnh tiếp theo (đừng commit).
3. Tải về một bản sao từ trước khi có sự cố, ví dụ của thứ Hai:

   ```bash
   npx wrangler r2 object get tg-s3-self-backup/d1/Mon.sql --remote --file backup.sql
   ```

4. Nạp bản sao, rồi chỉ áp dụng các migration mới hơn bản sao đó:

   ```bash
   npx wrangler d1 execute tg-s3-self-db --remote --file backup.sql
   npx wrangler d1 migrations apply tg-s3-self-db --remote
   ```

5. Kiểm tra số lượng, rồi xoá file trên máy (nó chứa chat ID, key của object và share token) và đặt lại `database_id` thành `""`:

   ```bash
   npx wrangler d1 execute tg-s3-self-db --remote --command "SELECT (SELECT count(*) FROM objects) AS objects, (SELECT count(*) FROM buckets) AS buckets"
   rm backup.sql
   ```

6. Chạy lại **Deploy to Cloudflare Workers**: workflow tìm database mới theo tên và gắn Worker vào đó (migration đã được áp dụng sẵn).
7. Tạo S3 key mới trong Mini App và cập nhật các client. Khi mọi thứ đã ổn, đặt lại `WEB_UPLOAD_BUCKET` (hoặc xoá Variable) rồi chạy lại workflow.

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

Thay `https://files.example.com` bằng URL Worker của bạn. Xem log trực tiếp: `npx wrangler tail tg-s3-self`; log được lưu lại của Worker (kết quả cron và lỗi, không có log từng request) nằm trong dashboard ở mục **Logs** của Worker. Chi tiết tương thích S3 (tiếng Anh): [S3-COMPAT.md](S3-COMPAT.md).
