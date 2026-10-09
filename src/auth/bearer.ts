import type { Env } from '../types';
import { timingSafeEqual } from '../utils/crypto';

export async function verifyBearer(request: Request, env: Env): Promise<boolean> {
  const auth = request.headers.get('Authorization');
  if (!auth) return false;
  const parts = auth.split(' ');
  if (parts.length !== 2 || parts[0] !== 'Bearer') return false;

  // Validate as Telegram WebApp initData (HMAC-SHA256)
  if (!(await verifyTelegramInitData(parts[1], env.TG_BOT_TOKEN))) return false;

  // A valid signature only proves the data comes from Telegram for this bot (any user can open the Mini App).
  // Apply the same allow-list as the bot webhook: TG_ADMIN_IDS.
  if (!env.TG_ADMIN_IDS) return true;
  let userId: unknown;
  try {
    userId = JSON.parse(new URLSearchParams(parts[1]).get('user') || '{}').id;
  } catch {
    return false;
  }
  return env.TG_ADMIN_IDS.split(',').map(id => id.trim()).includes(String(userId));
}

/**
 * Validate Telegram WebApp initData per:
 * https://core.telegram.org/bots/webapps#validating-data-received-via-the-mini-app
 *
 * 1. Parse initData as query params, extract `hash`
 * 2. Sort remaining params alphabetically, join with \n as data_check_string
 * 3. secret_key = HMAC-SHA256("WebAppData", bot_token)
 * 4. Verify HMAC-SHA256(data_check_string, secret_key) === hash
 * 5. Check auth_date freshness (allow up to 1 hour)
 */
async function verifyTelegramInitData(initData: string, botToken: string): Promise<boolean> {
  try {
    const params = new URLSearchParams(initData);
    const hash = params.get('hash');
    if (!hash) return false;

    // auth_date is mandatory per Telegram docs; reject if missing
    const authDate = params.get('auth_date');
    if (!authDate) return false;
    const age = Math.floor(Date.now() / 1000) - parseInt(authDate, 10);
    if (isNaN(age) || age > 3600 || age < -60) return false;

    // Build data_check_string: sorted params excluding hash, joined by \n
    params.delete('hash');
    const entries = Array.from(params.entries()).sort(([a], [b]) => a.localeCompare(b));
    const dataCheckString = entries.map(([k, v]) => `${k}=${v}`).join('\n');

    // secret_key = HMAC-SHA256("WebAppData", bot_token)
    const encoder = new TextEncoder();
    const secretKey = await crypto.subtle.importKey(
      'raw', encoder.encode('WebAppData'), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
    );
    const secretBuf = await crypto.subtle.sign('HMAC', secretKey, encoder.encode(botToken));

    // computed_hash = HMAC-SHA256(data_check_string, secret_key)
    const signingKey = await crypto.subtle.importKey(
      'raw', secretBuf, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
    );
    const sig = await crypto.subtle.sign('HMAC', signingKey, encoder.encode(dataCheckString));

    // Compare hex (timing-safe)
    const computed = Array.from(new Uint8Array(sig), b => b.toString(16).padStart(2, '0')).join('');
    return computed.length === hash.length && timingSafeEqual(computed, hash);
  } catch {
    return false;
  }
}
