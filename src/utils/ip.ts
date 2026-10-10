// Pure helper, no imports: unit-tested with `node --test`.

/**
 * Rate-limit key for a client address. IPv6 clients usually own a whole /64,
 * so they are limited per /64 prefix; IPv4 per address.
 */
export function rateLimitKey(ip: string | null): string {
  const addr = (ip ?? '').trim();
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(addr)) return addr;
  if (!addr.includes(':') || !/^[0-9a-fA-F:.]+$/.test(addr)) return 'unknown';

  const halves = addr.toLowerCase().split('::');
  if (halves.length > 2) return 'unknown';
  const head = halves[0] ? halves[0].split(':') : [];
  const tail = halves.length === 2 && halves[1] ? halves[1].split(':') : [];
  const fill = halves.length === 2 ? Array(Math.max(0, 8 - head.length - tail.length)).fill('0') : [];
  const groups = [...head, ...fill, ...tail];
  if (groups.length < 4) return 'unknown';
  return `${groups.slice(0, 4).map(g => g.replace(/^0+(?=.)/, '') || '0').join(':')}::/64`;
}
