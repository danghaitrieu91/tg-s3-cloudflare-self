# Lệnh của Telegram Bot

[English](bot-commands.md) | **Tiếng Việt**

## Tổng quan

Bot là giao diện Telegram cho kho lưu trữ của bạn: xem bucket, tải file lên, tạo link chia sẻ và xoá file ngay trong khung chat.

- **Chỉ dùng trong chat riêng.** Bot chỉ trả lời khi bạn nhắn trực tiếp (chat riêng) với nó. Tin nhắn trong group và channel — kể cả supergroup lưu trữ đặt trong `DEFAULT_CHAT_ID` — đều bị bỏ qua.
- **Chỉ người được cho phép.** Chỉ những Telegram user ID có trong `TG_ADMIN_IDS` (phân tách bằng dấu phẩy) mới dùng được bot; người khác nhận thông báo "Access denied". Danh sách này cũng áp dụng cho Mini App: API của Mini App chỉ chấp nhận các user ID đó. Không có phân quyền theo từng lệnh: mọi người được cho phép đều chạy được mọi lệnh, kể cả `/delete`. Cả workflow GitHub Actions lẫn `deploy.sh` đều từ chối deploy nếu thiếu `TG_ADMIN_IDS`; nếu secret này bị xoá khỏi Worker, bot và Mini App sẽ chấp nhận **bất kỳ** người dùng Telegram nào. Xem [configuration.vi.md](configuration.vi.md).
- **Ngôn ngữ.** Bot trả lời bằng tiếng Anh, tiếng Trung, tiếng Nhật hoặc tiếng Pháp tuỳ theo ngôn ngữ của ứng dụng Telegram; các ngôn ngữ khác (kể cả tiếng Việt) sẽ dùng tiếng Anh.
- **Lệnh không xác định** bị bỏ qua, không phản hồi. Tin nhắn văn bản thường nhận một gợi ý ngắn; các loại tin nhắn không hỗ trợ (sticker, vị trí, …) nhận thông báo "không hỗ trợ".

### Menu lệnh

Quá trình deploy không đăng ký menu lệnh với Telegram. Muốn có gợi ý tự động khi gõ `/`, hãy gửi `/setcommands` cho [@BotFather](https://t.me/BotFather), chọn bot của bạn rồi dán:

```
buckets - List all buckets
ls - List files in a bucket
info - Show file details
search - Search files in a bucket
share - Create a share link
shares - List share links
revoke - Revoke a share link
delete - Delete a file
stats - Storage statistics
setbucket - Set the default upload bucket
miniapp - Open the file manager
help - Show help
```

(Bạn có thể viết phần mô tả bằng tiếng Việt nếu muốn; chỉ tên lệnh bên trái là cố định.)

## Danh sách lệnh

Bot nhận đúng 13 lệnh dưới đây. Lệnh có hậu tố `@tên_bot` (ví dụ `/ls@my_bot`) vẫn được chấp nhận.

| Lệnh | Tham số | Công dụng |
|---|---|---|
| `/start` | — | Lời chào |
| `/help` | — | Hướng dẫn đầy đủ các lệnh |
| `/buckets` | — | Liệt kê bucket |
| `/ls` | `<bucket> [prefix] [page]` | Liệt kê file và thư mục |
| `/info` | `<bucket> <key>` | Chi tiết file |
| `/search` | `<bucket> <query>` | Tìm key trong một bucket |
| `/share` | `<bucket> <key> [seconds] [password] [max_downloads]` | Tạo link chia sẻ |
| `/shares` | `[bucket]` | Liệt kê link chia sẻ |
| `/revoke` | `<token>` | Thu hồi link chia sẻ (có xác nhận) |
| `/delete` | `<bucket> <key>` | Xoá file (có xác nhận) |
| `/stats` | — | Thống kê dung lượng |
| `/setbucket` | `[bucket]` | Xem hoặc đặt bucket mặc định khi tải lên |
| `/miniapp` | — | Mở trình quản lý file Mini App |

Key có thể chứa dấu cách: mọi thứ sau tên bucket đều được coi là key (trừ các tuỳ chọn ở cuối của `/ls` và `/share`, mô tả bên dưới).

### /start

Hiển thị lời chào kèm hướng dẫn nhanh.

### /help

Hiển thị hướng dẫn đầy đủ các lệnh kèm ví dụ.

### /buckets

Liệt kê mọi bucket cùng số file và tổng dung lượng (và mô tả, nếu có).

```
/buckets
```

### /ls

Liệt kê nội dung bucket theo kiểu thư mục (dấu phân cách là `/`), 20 mục mỗi trang.

```
/ls <bucket> [prefix] [page]
```

- `prefix` lọc theo tiền tố của key; kết thúc bằng `/` để mở một "thư mục".
- `page` chỉ được đọc khi có kèm prefix (`/ls photos 2024/ 2`). Danh sách dài sẽ có thêm nút **« Page N** / **Page N »**.

```
/ls photos
/ls photos 2024/january/
/ls photos 2024/ 2
```

### /info

Hiển thị tên file, bucket, dung lượng, content type, ETag và thời điểm sửa đổi gần nhất.

```
/info <bucket> <key>
```

### /search

Tìm các file trong một bucket có key chứa chuỗi cần tìm (so khớp chuỗi con; không phân biệt hoa thường với chữ cái ASCII). Hiển thị tối đa 20 kết quả.

```
/search <bucket> <query>
```

### /share

Tạo link chia sẻ cho một file.

```
/share <bucket> <key> [seconds] [password] [max_downloads]
```

Các tuỳ chọn được đọc từ cuối tin nhắn:

| Ví dụ | Kết quả |
|---|---|
| `/share docs report.pdf` | Link vĩnh viễn, không mật khẩu, tải không giới hạn |
| `/share docs report.pdf 86400` | Hết hạn sau 86400 giây (1 ngày) |
| `/share docs report.pdf mypass 10` | Mật khẩu `mypass`, tối đa 10 lượt tải, không hết hạn |
| `/share docs report.pdf 86400 mypass 10` | Cả ba tuỳ chọn |

Lưu ý:

- Mật khẩu không được chỉ gồm chữ số, nếu không sẽ bị hiểu là một con số.
- Nếu bản thân key kết thúc bằng dấu cách và một dãy số, dãy số đó sẽ bị hiểu là tuỳ chọn. Với những key như vậy, hãy dùng Mini App hoặc S3 API.

Link có dạng `https://<worker-host>/share/<token>`, trong đó `<worker-host>` là host đã đăng ký webhook (URL `*.workers.dev` hoặc tên miền riêng của bạn). Các dạng link:

- `/share/<token>` — trang xem trước kèm thông tin file
- `/share/<token>/download` — tải trực tiếp
- `/share/<token>/inline` — hiển thị trực tiếp trong trình duyệt (ảnh, video)
- `/share/<token>/live-video` — phần video của Apple Live Photo (chỉ khi có)

### /shares

Liệt kê link chia sẻ, 20 link mỗi trang kèm nút **« Page N** / **Page N »**.

```
/shares [bucket]
```

- Không có bucket: link chia sẻ của tất cả bucket.
- Có bucket: chỉ của bucket đó.

Mỗi mục gồm key của file, số lượt tải (và giới hạn, nếu có), token và link. Link đã hết hạn vẫn được liệt kê, có đánh dấu hết hạn, cho đến khi bạn thu hồi.

### /revoke

Thu hồi một link chia sẻ để nó ngừng hoạt động ngay lập tức. Bot sẽ hỏi xác nhận bằng nút **Confirm revoke** / **Cancel**.

```
/revoke <token>
```

### /delete

Xoá một file. Bot sẽ hỏi xác nhận bằng nút **Confirm delete** / **Cancel**.

```
/delete <bucket> <key>
```

Xoá theo kiểu dây chuyền: tin nhắn Telegram và các phần (chunk) đã lưu, các file phái sinh (thumbnail, bản chuyển mã), link chia sẻ của file và các bản cache cũng bị xoá theo.

### /stats

Hiển thị số bucket, tổng số file và tổng dung lượng.

```
/stats
```

### /setbucket

Xem hoặc đặt bucket nhận các file bạn gửi cho bot. Thiết lập được lưu riêng cho từng chat.

```
/setbucket            # xem bucket mặc định hiện tại và danh sách bucket
/setbucket <bucket>   # đặt bucket mặc định
```

Bucket phải tồn tại sẵn. Bạn có thể đặt một bucket công khai ở đây, nhưng khi đó mọi file bạn gửi cho bot đều ai cũng đọc được.

### /miniapp

Gửi một nút mở Telegram Mini App (`https://<worker-host>/miniapp`) — trình quản lý file có giao diện đồ hoạ, có thể tạo bucket, tải lên, đổi tên, chia sẻ và xoá file.

```
/miniapp
```

## Tải file lên

Gửi file cho bot trong chat riêng để lưu trữ. Hỗ trợ: tài liệu (document), ảnh, video, audio và tin nhắn thoại.

- **Bucket đích:** bucket mặc định đặt bằng `/setbucket`; nếu chưa đặt (hoặc bucket đó không còn), dùng bucket **riêng tư** đầu tiên trong `/buckets`. Bucket công khai — ví dụ bucket upload web `files`, vốn được tạo ở chế độ công khai — không bao giờ được chọn ngầm. Nếu chưa có bucket nào, bot sẽ yêu cầu bạn tạo trước (qua Mini App hoặc S3 API); nếu chỉ có bucket công khai, bot yêu cầu bạn tạo một bucket riêng tư hoặc chọn bucket bằng `/setbucket`.
- **Key:** tên file gốc. Ảnh được đặt tên `photo_<timestamp>.jpg`, tin nhắn thoại `voice_<timestamp>.ogg`. Nếu key đã tồn tại, hậu tố `_<timestamp>` được thêm trước phần mở rộng thay vì ghi đè.
- **Ảnh:** ảnh gửi dạng ảnh nén được lưu ở độ phân giải lớn nhất Telegram cung cấp; bot sẽ gợi ý gửi dạng file để giữ chất lượng gốc.
- **Trùng lặp:** nếu đúng file Telegram đó đã được lưu, bot báo vị trí hiện có thay vì lưu lại.
- **Giới hạn dung lượng:** file lớn hơn 20 MB bị từ chối, trừ khi đã cấu hình processor tuỳ chọn (`VPS_URL`). Xem [deployment.vi.md](deployment.vi.md).

Sau khi tải lên thành công, tin trả lời có hai nút: **Share** (tạo link vĩnh viễn, không mật khẩu, không giới hạn lượt tải) và **Detail** (giống kết quả của `/info`).

## Nút bấm tương tác

Các nút inline bot sử dụng:

- **Xác nhận xoá** — sau `/delete`
- **Xác nhận thu hồi** — sau `/revoke`
- **Phân trang** — « Page N / Page N » ở `/ls` và `/shares`
- **Share / Detail** — sau khi tải file lên

Dữ liệu của nút được giữ trong bộ nhớ của Worker: nút xác nhận xoá và thu hồi hết hạn sau 5 phút, các nút khác sau 10 phút, và bất kỳ nút nào cũng có thể hết hạn sớm hơn khi Cloudflare khởi động lại instance của Worker. Nếu nút không phản hồi hoặc báo đã hết hạn, hãy chạy lại lệnh.
