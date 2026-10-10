// Cron health helpers: admin alerts over the bot and webhook self-heal.
// Never put raw exception text into alert lines: fetch errors can carry the URL with the bot token.
import type { Env } from '../types';
import { escHtml } from '../utils/format';
import { deriveWebhookSecret } from '../utils/crypto';

const TG_API = 'https://api.telegram.org';
const TIMEOUT_MS = 10_000;
const MAX_ALERT_CHARS = 3500;
const WEBHOOK_ERROR_WINDOW_S = 6 * 3600;

/** WORKER_URL normalized to an origin with scheme and no trailing slash, or null when unset. */
export function workerBaseUrl(env: Env): string | null {
  const raw = env.WORKER_URL?.trim().replace(/\/+$/, '');
  if (!raw) return null;
  return raw.startsWith('http') ? raw : `https://${raw}`;
}

interface TgReply<T> { ok?: boolean; result?: T }
interface WebhookInfo { url?: unknown; last_error_date?: number; last_error_message?: string }

async function tgCall<T>(env: Env, method: string, body?: unknown): Promise<{ status: number; data: TgReply<T> | null }> {
  const res = await fetch(`${TG_API}/bot${env.TG_BOT_TOKEN}/${method}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body ?? {}),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  // Unchecked shape; every caller checks `ok === true` and the fields it reads.
  const data = (await res.json().catch(() => null)) as TgReply<T> | null;
  return { status: res.status, data: res.ok ? data : null };
}

/** Send one DM per admin. Never throws; returns how many admins got it. */
export async function notifyAdmins(env: Env, lines: string[]): Promise<{ admins: number; delivered: number }> {
  const admins = (env.TG_ADMIN_IDS ?? '').split(',').map(s => s.trim()).filter(Boolean);
  let text = '⚠️ <b>tg-s3 cron</b>';
  for (const line of lines) {
    const next = `${text}\n${escHtml(line)}`;
    if (next.length > MAX_ALERT_CHARS) continue; // whole lines only: never cut inside an HTML entity
    text = next;
  }
  let delivered = 0;
  for (const chatId of admins) {
    try {
      const r = await tgCall(env, 'sendMessage', { chat_id: chatId, text, parse_mode: 'HTML', disable_web_page_preview: true });
      if (r.data?.ok === true) delivered++;
      else console.error(`notifyAdmins: sendMessage failed (HTTP ${r.status})`);
    } catch {
      console.error('notifyAdmins: sendMessage request failed');
    }
  }
  if (delivered < admins.length) console.error(`alerts undelivered: ${admins.length - delivered}`);
  return { admins: admins.length, delivered };
}

/**
 * Check the Telegram webhook. Re-registers ONLY when no webhook is set at all;
 * a webhook pointing elsewhere may belong to another deployment of the same bot.
 * Returns an alert line, or null when healthy.
 */
export async function checkWebhook(env: Env): Promise<string | null> {
  const base = workerBaseUrl(env);
  if (!base) return 'WORKER_URL not set: webhook self-heal disabled.';
  const expected = `${base}/bot/webhook`;

  let info: { status: number; data: TgReply<WebhookInfo> | null };
  try {
    info = await tgCall<WebhookInfo>(env, 'getWebhookInfo');
  } catch {
    return 'Webhook: getWebhookInfo request failed.';
  }
  const result = info.data?.ok === true ? info.data.result : undefined;
  if (!result || typeof result.url !== 'string') {
    return `Webhook: getWebhookInfo failed (HTTP ${info.status}).`;
  }

  if (result.url === '') {
    try {
      // Same body as CI (deploy.yml): no allowed_updates, no setMyCommands
      const r = await tgCall(env, 'setWebhook', { url: expected, secret_token: await deriveWebhookSecret(env.TG_BOT_TOKEN) });
      return r.data?.ok === true
        ? 'Webhook was missing → re-registered.'
        : `Webhook re-register FAILED (HTTP ${r.status}).`;
    } catch {
      return 'Webhook re-register FAILED (request error).';
    }
  }
  if (result.url !== expected) {
    let host = 'unknown host';
    try { host = new URL(result.url).host; } catch { /* keep default */ }
    return `Webhook points to another host (${host}); not changed.`;
  }
  if (result.last_error_date && Date.now() / 1000 - result.last_error_date < WEBHOOK_ERROR_WINDOW_S) {
    return `Webhook error: ${(result.last_error_message ?? 'unknown').slice(0, 200)}`;
  }
  return null;
}
