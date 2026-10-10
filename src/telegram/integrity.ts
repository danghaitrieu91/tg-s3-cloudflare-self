// Pure decision logic for the cron getFile probe. No imports: unit-tested with `node --test`.
//
// The probe NEVER deletes. Telegram answers getFile with the same 400
// "wrong file_id or the file is temporarily unavailable" for a lost file, a file_id
// that belongs to another bot, and transient failures, so a 400 is a reason to tell
// an admin, never proof of loss. Classification uses the HTTP status only; the
// message text is only checked for "too big" (healthy > 20 MB file on the cloud API).

/** Outcome of one failed probe. There is deliberately no "delete" outcome. */
export type ProbeFailure = 'bad400' | 'unauthorized' | 'transient';

export function classifyProbeError(status: number | undefined, message: string): ProbeFailure {
  if (status === 400 && !/too big/i.test(message)) return 'bad400';
  if (status === 401) return 'unauthorized';
  return 'transient';
}

export interface ProbeResult {
  probed: number;
  bad400: Array<{ bucket: string; key: string }>;
  unauthorized: number;
  transient: number;
}

const MAX_LISTED = 10;
const MAX_KEY_CHARS = 200;

/** Plain-text alert lines (not HTML-escaped), diagnosis first, then affected keys. Empty array = nothing to report. */
export function probeIssues(r: ProbeResult): string[] {
  const lines: string[] = [];
  if (r.probed >= 3 && r.bad400.length === r.probed) {
    lines.push('All probes returned 400: TG_BOT_TOKEN is valid but probably belongs to a different bot (file_id is bot-specific).');
  }
  if (r.unauthorized > 0) {
    lines.push(`getFile returned 401 for ${r.unauthorized} of ${r.probed} sampled: TG_BOT_TOKEN invalid or revoked.`);
  }
  if (r.probed >= 3 && r.transient / r.probed >= 0.5) {
    lines.push(`Telegram unreachable or degraded: ${r.transient} of ${r.probed} probes failed transiently.`);
  }
  if (r.bad400.length > 0) {
    lines.push(`getFile 400 for ${r.bad400.length} of ${r.probed} sampled (lost, or not readable by this bot). Nothing was deleted.`);
    for (const o of r.bad400.slice(0, MAX_LISTED)) {
      const name = `${o.bucket}/${o.key}`;
      // Whole line (incl. "- ") stays within MAX_KEY_CHARS
      lines.push(`- ${name.length > MAX_KEY_CHARS - 2 ? name.slice(0, MAX_KEY_CHARS - 3) + '…' : name}`);
    }
  }
  return lines;
}
