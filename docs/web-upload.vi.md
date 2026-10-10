# Web upload (tải lên qua web)

[English](web-upload.md) | **Tiếng Việt**

Worker phục vụ một trang kéo-thả đơn giản tại `/`. Ai mở trang cũng có thể tải lên một file (tối đa 20 MB) và nhận lại link công khai tới file đó. Không cần đăng nhập.

> [!WARNING]
> **Web upload được bật sẵn và là công khai.**
> 1. **Bất kỳ ai biết URL Worker của bạn đều có thể tải file lên** (mỗi file ≤ 20 MB) và nhận link công khai. Trang này **không cần đăng nhập**; giới hạn tích hợp duy nhất là 30 lượt tải lên mỗi phút cho mỗi IP ([chi tiết](#giới-hạn-tốc-độ-tích-hợp)), dễ dàng bị vượt qua khi dùng nhiều IP và **không** phải là biện pháp bảo vệ. Tính năng có thể bị lạm dụng (spam, nội dung phi pháp) và khiến bot hoặc nhóm Telegram của bạn bị khoá.
> 2. **Bảo vệ bằng Cloudflare**: [rate limiting rule của WAF](#phương-án-1-rate-limiting-rule-của-waf) và/hoặc [Cloudflare Access](#phương-án-2-cloudflare-access). Cả hai đều cần **tên miền riêng** thuộc một zone trên Cloudflare — chúng không bảo vệ URL `*.workers.dev`, nên phải tắt URL đó.
> 3. **Hoặc tắt hẳn**: đặt GitHub Variable `WEB_UPLOAD_BUCKET` thành `off` rồi chạy lại workflow (nếu dùng `deploy.sh`: đặt `WEB_UPLOAD_BUCKET = "off"` trong `wrangler.toml`).

## Cách hoạt động

| Mục | Hành vi |
|-----|---------|
| Route | `GET /` (và `/index.html`) — trang tải lên; `POST /api/web-upload?name=<tên-file>` — endpoint tải lên (nội dung file nằm nguyên trong body). Trang chỉ được trả về cho request không xác thực: request S3 có chữ ký tới `/` (ListBuckets, ví dụ `aws s3 ls`) hoặc presigned URL vẫn đi tới S3 API như bình thường |
| Mặc định | **BẬT**: `WEB_UPLOAD_BUCKET = "files"` trong `wrangler.toml` |
| Giới hạn kích thước | 20 MB, kiểm tra cả header `Content-Length` lẫn số byte thực nhận (`413` nếu vượt) |
| Xác thực | Không có. Giới hạn 30 request mỗi 60 giây cho mỗi client, xem [Giới hạn tốc độ tích hợp](#giới-hạn-tốc-độ-tích-hợp) |
| Bucket | Giá trị của `WEB_UPLOAD_BUCKET` (chuyển thành chữ thường). Giá trị phải là tên bucket hợp lệ (`^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$` sau khi chuyển chữ thường), nếu không mọi lần tải lên đều lỗi `500`. Nếu bucket chưa tồn tại, nó được tạo ở lần tải lên đầu tiên dưới dạng bucket **công khai** trong `DEFAULT_CHAT_ID` (một lệnh insert nguyên tử, nên các lần tải lên đồng thời không tạo trùng) |
| Bucket riêng tư đã có | Không bao giờ bị chuyển thành công khai. Tải lên sẽ lỗi `403` (`Web upload bucket is private; make it public or set WEB_UPLOAD_BUCKET=off`) |
| Key của object | `YYYYMMDD_<tên-đã-làm-sạch>_<4 ký tự hex ngẫu nhiên>.<phần-mở-rộng>`, ví dụ `20261009_holiday_photo_3f9a.jpg`. Phần mở rộng được làm sạch giống tên file (chỉ giữ `a-z`, `0-9`, `.`, `-`) |
| Content-Type | Chỉ giữ kiểu được khai báo cho ảnh (`png`, `jpeg`, `gif`, `webp`, `avif`, `bmp`, `heic`, `heif`), `video/*`, `audio/*`, `application/pdf` và `text/plain`. Mọi kiểu khác (HTML, SVG, JavaScript, XML, kiểu không rõ) được lưu thành `application/octet-stream`, nên trình duyệt tải file về thay vì hiển thị. Điều này ngăn việc dùng trang để đặt trang lừa đảo (phishing) hoặc script trên tên miền của bạn |
| Link trả về | `https://<worker-host>/<bucket>/<key>` — ai cũng đọc được vì bucket là công khai |

File tải lên là object bình thường: bạn có thể xem và xoá chúng bằng bot, Mini App hoặc bất kỳ S3 client nào.

## Giới hạn tốc độ tích hợp

`POST /api/web-upload` đi qua binding Workers Rate Limiting `WEB_UPLOAD_LIMITER` (`[[ratelimits]]` trong `wrangler.toml`):

| Mục | Hành vi |
|-----|---------|
| Giới hạn | 30 request mỗi 60 giây cho mỗi client |
| Khoá client | Địa chỉ IPv4, hoặc dải IPv6 **/64** (một người dùng IPv6 thường sở hữu cả một dải /64) |
| Khi vượt giới hạn | `429` kèm `Retry-After: 60`, trả về trước khi đọc body của request |
| Trang tải lên | Khi gặp `429`, trang hiện `Rate limited, waiting Ns…`, chờ rồi gửi lại chính file đó, tối đa 3 lần |

Đây **chỉ là biện pháp làm chậm**, không phải bảo vệ. Bộ đếm được giữ riêng ở từng vị trí (location) của Cloudflare và chỉ nhất quán sau một khoảng thời gian (eventually consistent), nên vài request dư vẫn có thể lọt qua, còn kẻ tấn công có nhiều địa chỉ IP thì hoàn toàn không bị chặn. Nếu chính bộ giới hạn bị lỗi, lượt tải lên vẫn được cho qua (fail open). Muốn bảo vệ thật sự, hãy tắt trang hoặc dùng [Cloudflare Access](#phương-án-2-cloudflare-access) trên tên miền riêng.

Muốn đổi giới hạn, sửa `limit` và/hoặc `period` trong `wrangler.toml` rồi deploy lại (`period` phải là `10` hoặc `60`):

```toml
[[ratelimits]]
name = "WEB_UPLOAD_LIMITER"
namespace_id = "73201"
simple = { limit = 30, period = 60 }
```

`namespace_id` có phạm vi toàn tài khoản: hãy giữ giá trị này không trùng giữa các Worker của bạn, nếu không chúng sẽ dùng chung bộ đếm.

## Tắt hoặc đổi bucket

`WEB_UPLOAD_BUCKET` nhận các giá trị:

| Giá trị | Kết quả |
|---------|---------|
| không đặt / `files` | BẬT, bucket `files` (mặc định) |
| `off` (không phân biệt hoa/thường) hoặc rỗng | TẮT: `/` và `/api/web-upload` không còn được tính năng web upload phục vụ |
| tên bucket hợp lệ khác | BẬT, file được tải vào bucket đó |

### GitHub Actions

Fork → **Settings → Secrets and variables → Actions → Variables** → đặt `WEB_UPLOAD_BUCKET` (ví dụ `off`), rồi chạy lại workflow **Deploy to Cloudflare Workers**. Lần chạy sẽ in thông báo cho biết web upload đang BẬT hay TẮT. Xoá Variable thì giá trị trong `wrangler.toml` (`files`) được dùng lại.

### deploy.sh và wrangler.toml

`deploy.sh` **không** đọc `WEB_UPLOAD_BUCKET` từ `.env`. Hãy sửa `wrangler.toml` rồi chạy lại `./deploy.sh`:

```toml
[vars]
WEB_UPLOAD_BUCKET = "off"
```

## Bảo vệ web upload

### Trước khi bắt đầu: tên miền riêng và workers.dev

- Rate limiting rule của WAF được tạo theo từng **zone** (tên miền của bạn) trong dashboard ([Create a rate limiting rule in the dashboard](https://developers.cloudflare.com/waf/rate-limiting-rules/create-zone-dashboard/)), còn ứng dụng Access dạng self-hosted cần một tên miền là zone đang hoạt động trong tài khoản Cloudflare ([Publish a self-hosted application](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/self-hosted-public-app/)). Vì vậy trước hết hãy chạy Worker trên tên miền riêng, ví dụ `files.example.com`.
- Các lớp bảo vệ dưới đây chỉ áp dụng cho hostname đó. Nếu `tg-s3-self.<subdomain-của-bạn>.workers.dev` vẫn bật, đó là một đường thứ hai, **không được bảo vệ**, để gọi `/api/web-upload`. Hãy tắt nó:
  - **GitHub Actions**: đặt Variable `CUSTOM_DOMAIN` thì CI tự thêm Custom Domain và đặt `workers_dev = false`.
  - **`deploy.sh`**: tự thêm route và `workers_dev = false` vào `wrangler.toml` (xem [deployment.vi.md](deployment.vi.md#tên-miền-riêng-và-tunnel)).
- `workers_dev = false` sẽ tắt route `workers.dev` ở lần deploy kế tiếp; nếu chỉ tắt trong dashboard thì lần `wrangler deploy` sau sẽ bật lại. Thiết lập này không tắt Version URL và Preview URL ([workers.dev](https://developers.cloudflare.com/workers/configuration/routing/workers-dev/)).

### Phương án 1: Rate limiting rule của WAF

Rate limiting rule giới hạn tốc độ tải lên của từng client. Nó làm chậm việc lạm dụng chứ không chặn được kẻ kiên nhẫn (muốn chặn hẳn, hãy dùng Access).

Gói **Free** cho phép (nguồn: [Rate limiting rules — Availability](https://developers.cloudflare.com/waf/rate-limiting-rules/)):

| Thiết lập | Gói Free |
|-----------|----------|
| Số rule | 1 |
| Trường dùng trong biểu thức | Path, Verified Bot |
| Đặc điểm đếm (characteristic) | IP |
| Chu kỳ đếm | 10 giây |
| Thời gian chặn (duration) | 10 giây |

Các bước (nguồn: [Create a rate limiting rule in the dashboard](https://developers.cloudflare.com/waf/rate-limiting-rules/create-zone-dashboard/)):

1. Cloudflare dashboard → chọn tên miền của bạn → trang **Security rules**.
2. **Create rule** → **Rate limiting rules**.
3. **Rule name**: `web-upload`.
4. Biểu thức: **Field** `URI Path`, **Operator** `equals`, **Value** `/api/web-upload`.
5. **With the same characteristics**: `IP`.
6. **When rate exceeds**: ví dụ `5` request mỗi `10 seconds`.
7. **Then take action**: `Block`; **Duration**: `10 seconds`.
8. **Deploy**.

Bộ đếm của Cloudflare tính riêng theo từng data center và cập nhật trễ tới vài giây, nên vẫn có thể lọt thêm vài request ([Rate limiting rules — Important remarks](https://developers.cloudflare.com/waf/rate-limiting-rules/)). Các gói trả phí cho phép chu kỳ và thời gian chặn dài hơn (cùng nguồn).

### Phương án 2: Cloudflare Access

Cloudflare Access đặt một bước đăng nhập trước URL, nên chỉ những người bạn cho phép (ví dụ email của chính bạn) mới tải lên được.

**Chỉ bảo vệ path `/api/web-upload`.** Đừng bảo vệ cả hostname:

- Ứng dụng Access có **Path** để trống, hoặc là `/*`, sẽ bao phủ **mọi** path của hostname ([Application paths](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/app-paths/)). Khi đó Telegram không gọi được `/bot/webhook` (bot ngừng hoạt động), S3 client (path bucket/object), link chia sẻ công khai (`/share/*`), link bucket công khai và Mini App đều bị chặn — không thành phần nào trong số đó đăng nhập được.
- Path cụ thể hơn sẽ kế thừa rule của path cha nếu không có rule riêng, nên ứng dụng trên `/api/web-upload` bao phủ cả những gì nằm dưới `/api/web-upload/` và không gì khác ([Application paths](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/app-paths/)).
- Access không thể chỉ bảo vệ riêng trang `/` mà không bao phủ toàn bộ path bên dưới. Điều đó không sao: bảo vệ endpoint là đủ — trang vẫn hiển thị, nhưng muốn tải lên phải đăng nhập.
- **Đừng** dùng **Workers & Pages → Worker của bạn → Access → Protect this Worker behind Access**. Tuỳ chọn đó bảo vệ mọi tên miền của Worker (route, Custom Domain, `workers.dev`, preview) — tức là toàn bộ bot và S3 API ([Cloudflare Access for Workers](https://developers.cloudflare.com/workers/configuration/cloudflare-access/)). Hãy dùng ứng dụng theo hostname/path (cùng trang, mục "Protect a specific hostname, Custom Domain, or path").

Các bước (nguồn: [Publish a self-hosted application](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/self-hosted-public-app/); tài khoản phải thiết lập Zero Trust trước, xem [Cloudflare Access for Workers — Before you start](https://developers.cloudflare.com/workers/configuration/cloudflare-access/)):

1. Cloudflare dashboard → **Zero Trust** → **Access controls** → **Applications** → **Create new application**.
2. Chọn **Self-hosted and private** → **Add public hostname**.
3. **Domain**: tên miền riêng của bạn (ví dụ subdomain `files`, domain `example.com`); **Path**: `api/web-upload`.
4. **Access policies**: tạo policy **Allow** gồm (các) email của bạn. Ứng dụng Access từ chối mọi người không khớp một policy Allow.
5. Chọn (các) nhà cung cấp danh tính (identity provider) mà người dùng sẽ đăng nhập.
6. **Create**.

Cách dùng: trang tải lên gửi file bằng một request chạy nền, request này không thể hiển thị trang đăng nhập. Nếu không có cookie `CF_Authorization` hợp lệ, Access sẽ chặn request ([Authorization cookie](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/)). Vì vậy:

1. Mở `https://files.example.com/api/web-upload` trong trình duyệt một lần và đăng nhập. (Sau khi đăng nhập, Worker có thể báo lỗi cho URL đó — endpoint chỉ nhận `POST`. Điều này là bình thường.)
2. Vào `https://files.example.com/` và tải lên như thường lệ.

Cookie `CF_Authorization` có phạm vi theo hostname, trừ khi bật **Cookie Path Attribute** trong phần cookie settings của ứng dụng — hãy để tắt, nếu không cookie sẽ không được gửi từ trang `/` ([Authorization cookie — Cookie Path Attribute](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/)). Đăng nhập lại khi phiên hết hạn (mặc định 24 giờ, cùng nguồn).

### Phương án 3: Tắt hẳn

Nếu không cần trang này, hãy tắt nó — xem [Tắt hoặc đổi bucket](#tắt-hoặc-đổi-bucket). Bạn vẫn tải lên được bằng bot, Mini App hoặc bất kỳ S3 client nào.

## Lỗi thường gặp

| Mã | Trường `error` trong phản hồi | Ý nghĩa |
|----|-------------------------------|---------|
| `400` | `Empty file` | Body của request rỗng |
| `403` | `Web upload bucket is private; make it public or set WEB_UPLOAD_BUCKET=off` | Bucket đã cấu hình đang tồn tại và là riêng tư |
| `413` | `File exceeds 20MB limit` | File lớn hơn 20 MB |
| `500` | `WEB_UPLOAD_BUCKET is not a valid bucket name` | `WEB_UPLOAD_BUCKET` không phải tên bucket hợp lệ; sửa Variable / giá trị trong `wrangler.toml` rồi deploy lại |
| `500` | `Storage bucket not configured` | Không tạo hoặc đọc được bucket |
| `500` | `Failed to upload file to backend` | Gửi file lên Telegram hoặc lưu metadata thất bại (xem `npx wrangler tail tg-s3-self`) |

Liên quan: [configuration.vi.md](configuration.vi.md), [deployment.vi.md](deployment.vi.md).
