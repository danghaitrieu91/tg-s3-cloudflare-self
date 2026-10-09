# Telegram Bot Commands

**English** | [Tiếng Việt](bot-commands.vi.md)

## Overview

The bot is a Telegram front end for your storage: browse buckets, upload files, create share links, and delete objects from a chat.

- **Private chat only.** The bot answers only in a direct (private) chat with it. Messages in groups and channels — including the storage supergroup set in `DEFAULT_CHAT_ID` — are ignored.
- **Allowed users only.** Only Telegram user IDs listed in `TG_ADMIN_IDS` (comma-separated) can use the bot; everyone else gets "Access denied". The same list also applies to the Mini App: its API accepts only these user IDs. There are no per-command roles: every allowed user can run every command, including `/delete`. Both the GitHub Actions workflow and `deploy.sh` refuse to deploy without `TG_ADMIN_IDS`; if the secret is ever removed from the Worker, the bot and the Mini App accept **any** Telegram user. See [configuration.md](configuration.md).
- **Language.** Replies are in English, Chinese, Japanese, or French, chosen from your Telegram app language; any other language falls back to English.
- **Unknown commands** are ignored silently. Plain text gets a short hint; unsupported message types (stickers, locations, …) get an "unsupported" reply.

### Command menu

Deployment does not register the command menu with Telegram. To get autocomplete when typing `/`, send `/setcommands` to [@BotFather](https://t.me/BotFather), pick your bot, and paste:

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

## Commands

The bot recognises exactly these 13 commands. A `@botname` suffix (e.g. `/ls@my_bot`) is accepted.

| Command | Arguments | Purpose |
|---|---|---|
| `/start` | — | Welcome message |
| `/help` | — | Full command reference |
| `/buckets` | — | List buckets |
| `/ls` | `<bucket> [prefix] [page]` | List files and folders |
| `/info` | `<bucket> <key>` | File details |
| `/search` | `<bucket> <query>` | Search keys in a bucket |
| `/share` | `<bucket> <key> [seconds] [password] [max_downloads]` | Create a share link |
| `/shares` | `[bucket]` | List share links |
| `/revoke` | `<token>` | Revoke a share link (with confirmation) |
| `/delete` | `<bucket> <key>` | Delete a file (with confirmation) |
| `/stats` | — | Storage totals |
| `/setbucket` | `[bucket]` | Show or set the default upload bucket |
| `/miniapp` | — | Open the Mini App file manager |

Keys may contain spaces: everything after the bucket name is treated as the key (minus any trailing options for `/ls` and `/share`, described below).

### /start

Shows a welcome message with a short quick-start guide.

### /help

Shows the full command reference with examples.

### /buckets

Lists every bucket with its file count and total size (and description, if one is set).

```
/buckets
```

### /ls

Lists the contents of a bucket, folder-style (`/` is the delimiter), 20 entries per page.

```
/ls <bucket> [prefix] [page]
```

- `prefix` filters by key prefix; end it with `/` to open a "folder".
- `page` is only read when a prefix is also given (`/ls photos 2024/ 2`). Long listings also get **« Page N** / **Page N »** buttons.

```
/ls photos
/ls photos 2024/january/
/ls photos 2024/ 2
```

### /info

Shows a file's name, bucket, size, content type, ETag, and last-modified time.

```
/info <bucket> <key>
```

### /search

Finds files in one bucket whose key contains the query (substring match; case-insensitive for ASCII letters). Shows at most 20 results.

```
/search <bucket> <query>
```

### /share

Creates a share link for a file.

```
/share <bucket> <key> [seconds] [password] [max_downloads]
```

Options are read from the end of the message:

| Example | Result |
|---|---|
| `/share docs report.pdf` | Permanent link, no password, unlimited downloads |
| `/share docs report.pdf 86400` | Expires after 86400 s (1 day) |
| `/share docs report.pdf mypass 10` | Password `mypass`, at most 10 downloads, no expiry |
| `/share docs report.pdf 86400 mypass 10` | All three |

Notes:

- The password must not be purely numeric, otherwise it is read as a number.
- If the key itself ends with a space followed by digits, those digits are taken as an option. Use the Mini App or the S3 API for such keys.

The link is `https://<worker-host>/share/<token>`, where `<worker-host>` is the host the webhook is registered on (your `*.workers.dev` URL or custom domain). Available forms:

- `/share/<token>` — preview page with file details
- `/share/<token>/download` — direct download
- `/share/<token>/inline` — inline display (images, video)
- `/share/<token>/live-video` — video part of an Apple Live Photo (only when one exists)

### /shares

Lists share links, 20 per page with **« Page N** / **Page N »** buttons.

```
/shares [bucket]
```

- Without a bucket: share links of all buckets.
- With a bucket: only that bucket.

Each entry shows the file key, download count (and limit, if any), the token, and the link. Expired links are still listed and marked as expired until you revoke them.

### /revoke

Revokes a share link so it stops working immediately. The bot asks for confirmation with **Confirm revoke** / **Cancel** buttons.

```
/revoke <token>
```

### /delete

Deletes a file. The bot asks for confirmation with **Confirm delete** / **Cancel** buttons.

```
/delete <bucket> <key>
```

Deletion cascades: the stored Telegram message(s) and chunks, derived objects (thumbnails, transcoded versions), the file's share links, and cached copies are removed as well.

### /stats

Shows the number of buckets, the total number of files, and the total size.

```
/stats
```

### /setbucket

Shows or sets the bucket that files you send to the bot are uploaded to. The setting is stored per chat.

```
/setbucket            # show the current default and the list of buckets
/setbucket <bucket>   # set the default
```

The bucket must already exist. Setting a public bucket here is allowed, but then everything you send to the bot is publicly readable.

### /miniapp

Sends a button that opens the Telegram Mini App (`https://<worker-host>/miniapp`), a graphical file manager that can also create buckets, upload, rename, share, and delete files.

```
/miniapp
```

## File Upload

Send a file to the bot in the private chat to store it. Supported: documents, photos, videos, audio, and voice messages.

- **Target bucket:** your `/setbucket` default; if none is set (or it no longer exists), the first **private** bucket shown by `/buckets`. Public buckets — for example the web upload bucket `files`, which is created public — are never chosen implicitly. If there are no buckets yet, the bot asks you to create one first (via the Mini App or the S3 API); if only public buckets exist, it asks you to create a private bucket or pick one with `/setbucket`.
- **Key:** the original filename. Photos get `photo_<timestamp>.jpg`, voice messages `voice_<timestamp>.ogg`. If the key already exists, a `_<timestamp>` suffix is added before the extension instead of overwriting.
- **Photos:** a photo sent as a compressed image is stored at the largest resolution Telegram provides; the bot suggests sending it as a file to keep the original quality.
- **Duplicates:** if the exact same Telegram file is already stored, the bot tells you where it is instead of storing it again.
- **Size limit:** files larger than 20 MB are rejected unless the optional processor (`VPS_URL`) is configured. See [deployment.md](deployment.md).

After a successful upload the reply has two buttons: **Share** (creates a permanent link with no password or download limit) and **Detail** (same output as `/info`).

## Callback Actions

Inline buttons used by the bot:

- **Delete confirmation** — after `/delete`
- **Revoke confirmation** — after `/revoke`
- **Pagination** — « Page N / Page N » on `/ls` and `/shares`
- **Share / Detail** — after an upload

Button data is kept in the Worker's memory: delete and revoke confirmations expire after 5 minutes, other buttons after 10 minutes, and any of them can expire earlier when Cloudflare restarts the Worker instance. If a button stops responding or says it has expired, run the command again.
