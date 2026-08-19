import { Cue } from '../shared/types';

export type SubFormat = 'json3' | 'vtt' | 'ttml' | 'srt' | 'unknown';

/** Sniff the format from the body itself — URLs lie, extensions are often absent. */
export function detectFormat(body: string, url = ''): SubFormat {
  const head = body.slice(0, 400).trimStart();
  if (!head) return 'unknown';
  if (head.startsWith('WEBVTT')) return 'vtt';
  if (head.startsWith('{')) return head.includes('"events"') || url.includes('timedtext') ? 'json3' : 'unknown';
  if (head.startsWith('<')) return 'ttml';
  if (/^\d+\s*\r?\n\d{2}:\d{2}:\d{2},\d{3}\s*-->/.test(head)) return 'srt';
  if (head.includes('-->')) return 'vtt';
  return 'unknown';
}

/** Parse any supported subtitle body into normalised cues. Returns [] on failure. */
export function parse(body: string, url = ''): Cue[] {
  try {
    switch (detectFormat(body, url)) {
      case 'json3': return normalise(parseJSON3(body));
      case 'vtt':   return normalise(parseVTT(body));
      case 'ttml':  return normalise(parseTTML(body));
      case 'srt':   return normalise(parseSRT(body));
      default:      return [];
    }
  } catch {
    return [];
  }
}

/* ── YouTube json3 ─────────────────────────────────────────────────────────── */

export function parseJSON3(json: string): Cue[] {
  const data = JSON.parse(json);
  const cues: Cue[] = [];
  for (const ev of data.events || []) {
    if (!ev.segs) continue;
    const text = ev.segs.map((s: { utf8?: string }) => s.utf8 || '').join('').replace(/\s+/g, ' ').trim();
    if (!text) continue;
    const start = (ev.tStartMs || 0) / 1000;
    cues.push({ start, end: start + (ev.dDurationMs || 0) / 1000, text });
  }
  return cues;
}

/* ── WebVTT ───────────────────────────────────────────────────────────────── */

export function parseVTT(vtt: string): Cue[] {
  const cues: Cue[] = [];
  // HLS subtitle segments carry an offset mapping; honour it when present.
  let offset = 0;
  const map = vtt.match(/X-TIMESTAMP-MAP\s*[:=]\s*(.+)/);
  if (map) {
    const local = map[1].match(/LOCAL:\s*([\d:.]+)/);
    const mpegts = map[1].match(/MPEGTS:\s*(\d+)/);
    if (local && mpegts) offset = Number(mpegts[1]) / 90000 - parseTime(local[1]);
  }

  for (const block of vtt.split(/\r?\n\r?\n+/)) {
    const lines = block.split(/\r?\n/).map(l => l.trim()).filter(Boolean);
    const i = lines.findIndex(l => l.includes('-->'));
    if (i === -1) continue;

    const [rawStart, rawRest] = lines[i].split('-->');
    // Trailing cue settings (align:middle, position:50%…) follow the end time.
    const rawEnd = (rawRest || '').trim().split(/\s+/)[0];
    const text = cleanText(lines.slice(i + 1).join('\n'));
    if (!text) continue;

    cues.push({
      start: parseTime(rawStart.trim()) + offset,
      end: parseTime(rawEnd) + offset,
      text,
    });
  }
  return cues;
}

export function parseSRT(srt: string): Cue[] {
  return parseVTT(srt.replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g, '$1.$2'));
}

/* ── TTML / EBU-TT / DFXP ─────────────────────────────────────────────────── */

export function parseTTML(xml: string): Cue[] {
  const doc = new DOMParser().parseFromString(xml, 'text/xml');
  if (doc.querySelector('parsererror')) return [];

  // EBU-TT may declare a frame rate, needed for hh:mm:ss:ff timecodes.
  const root = doc.documentElement;
  const fps = Number(
    root.getAttribute('ttp:frameRate') ||
    root.getAttributeNS('http://www.w3.org/ns/ttml#parameter', 'frameRate') ||
    25
  );

  let ps: Element[] = Array.from(doc.getElementsByTagNameNS('*', 'p'));
  if (ps.length === 0) ps = Array.from(doc.querySelectorAll('p'));

  const cues: Cue[] = [];
  for (const el of ps) {
    const begin = el.getAttribute('begin');
    if (!begin) continue;
    // <br/> inside a <p> is a line break, not a word boundary.
    const text = cleanText(el.innerHTML ? el.innerHTML.replace(/<br\s*\/?>/gi, '\n') : el.textContent || '');
    if (!text) continue;

    const start = parseTime(begin, fps);
    const endAttr = el.getAttribute('end');
    const durAttr = el.getAttribute('dur');
    const end = endAttr ? parseTime(endAttr, fps)
      : durAttr ? start + parseTime(durAttr, fps)
      : start + 4;
    cues.push({ start, end, text });
  }
  return cues;
}

/* ── Shared helpers ───────────────────────────────────────────────────────── */

/**
 * Handles hh:mm:ss.mmm, mm:ss.mmm, hh:mm:ss:ff (EBU-TT frames), and offset
 * forms like "12.5s" / "300ms" / "150f".
 */
function parseTime(ts: string, fps = 25): number {
  const s = ts.trim();
  if (!s) return 0;

  const offset = s.match(/^([\d.]+)(ms|s|m|h|f|t)$/);
  if (offset) {
    const n = parseFloat(offset[1]);
    switch (offset[2]) {
      case 'ms': return n / 1000;
      case 's': return n;
      case 'm': return n * 60;
      case 'h': return n * 3600;
      case 'f': return n / fps;
      default: return n;
    }
  }

  const parts = s.split(':');
  if (parts.length === 4) {
    // hh:mm:ss:ff — the last group is frames, not a fraction of a second.
    const [h, m, sec, f] = parts.map(Number);
    return h * 3600 + m * 60 + sec + (f || 0) / fps;
  }
  if (parts.length === 3) {
    const [h, m, sec] = parts;
    return Number(h) * 3600 + Number(m) * 60 + parseFloat(sec.replace(',', '.'));
  }
  if (parts.length === 2) {
    const [m, sec] = parts;
    return Number(m) * 60 + parseFloat(sec.replace(',', '.'));
  }
  return parseFloat(s) || 0;
}

const ENTITIES: Record<string, string> = {
  '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'", '&apos;': "'", '&nbsp;': ' ',
};

/** Strip markup and decode entities without ever touching innerHTML. */
function cleanText(raw: string): string {
  return raw
    .replace(/<[^>]*>/g, '')
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&[a-z]+;/gi, m => ENTITIES[m.toLowerCase()] ?? m)
    .replace(/[ \t]+/g, ' ')
    .replace(/\s*\n\s*/g, '\n')
    .trim();
}

/**
 * Sort, drop junk, clamp bad durations, and merge cues that are really one
 * line split across entries (common in broadcaster VTT).
 */
function normalise(cues: Cue[]): Cue[] {
  const out = cues
    .filter(c => c.text && c.text !== '.' && Number.isFinite(c.start))
    .map(c => ({
      start: Math.max(0, c.start),
      end: Number.isFinite(c.end) && c.end > c.start ? c.end : c.start + 3,
      text: c.text,
    }))
    .sort((a, b) => a.start - b.start);

  const merged: Cue[] = [];
  for (const c of out) {
    const prev = merged[merged.length - 1];
    // Identical text in back-to-back cues = the same line held on screen.
    if (prev && prev.text === c.text && c.start - prev.end < 0.4) {
      prev.end = Math.max(prev.end, c.end);
      continue;
    }
    merged.push(c);
  }
  return merged;
}

/** Binary search for the cue covering `t`; -1 if none. Used on every frame. */
export function cueIndexAt(cues: Cue[], t: number, hint = 0): number {
  if (cues.length === 0) return -1;
  // Playback is mostly sequential, so check around the previous answer first.
  for (let i = Math.max(0, hint); i < Math.min(cues.length, hint + 3); i++) {
    if (t >= cues[i].start && t <= cues[i].end) return i;
  }
  let lo = 0, hi = cues.length - 1, best = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (cues[mid].start <= t) { best = mid; lo = mid + 1; } else { hi = mid - 1; }
  }
  // `best` is the last cue starting at or before t; it counts only if not over.
  return best >= 0 && t <= cues[best].end ? best : -1;
}
