import { Cue } from './types';

export function parseYouTubeJSON(json: string): Cue[] {
  try {
    const data = JSON.parse(json);
    const events = data.events || [];
    const cues: Cue[] = [];

    for (const event of events) {
      if (!event.segs) continue;
      const text = event.segs.map((s: any) => s.utf8 || '').join('').trim();
      if (!text || text === '\n') continue;

      cues.push({
        start: (event.tStartMs || 0) / 1000,
        end: ((event.tStartMs || 0) + (event.dDurationMs || 0)) / 1000,
        text: text.replace(/\n/g, ' '),
      });
    }

    return cues;
  } catch {
    return [];
  }
}

export function parseYouTubeXML(xml: string): Cue[] {
  if (!xml || xml.trim().startsWith('{')) return parseYouTubeJSON(xml);

  const parser = new DOMParser();
  const doc = parser.parseFromString(xml, 'text/xml');
  const cues: Cue[] = [];

  const texts = doc.querySelectorAll('text');
  if (texts.length > 0) {
    texts.forEach(el => {
      const start = parseFloat(el.getAttribute('start') || '0');
      const dur = parseFloat(el.getAttribute('dur') || '0');
      const text = decodeHTMLEntities(el.textContent || '').trim();
      if (text) cues.push({ start, end: start + dur, text });
    });
    return cues;
  }

  const pTags = doc.querySelectorAll('p');
  pTags.forEach(el => {
    const t = parseInt(el.getAttribute('t') || '0', 10);
    const d = parseInt(el.getAttribute('d') || '0', 10);
    const text = decodeHTMLEntities(el.textContent || '').trim();
    if (text) cues.push({ start: t / 1000, end: (t + d) / 1000, text });
  });

  return cues;
}

export function parseVTT(vtt: string): Cue[] {
  const cues: Cue[] = [];
  const blocks = vtt.split(/\n\n+/);

  for (const block of blocks) {
    const lines = block.trim().split('\n');
    const timeLine = lines.find(l => l.includes('-->'));
    if (!timeLine) continue;

    const [startStr, endStr] = timeLine.split('-->').map(s => s.trim());
    const textLines = lines.slice(lines.indexOf(timeLine) + 1);
    const text = textLines.join(' ').replace(/<[^>]+>/g, '').trim();
    if (!text) continue;

    cues.push({
      start: parseTimestamp(startStr),
      end: parseTimestamp(endStr),
      text,
    });
  }

  return cues;
}

export function parseSRT(srt: string): Cue[] {
  return parseVTT(srt.replace(/,/g, '.'));
}

export function parseEBUTT(xml: string): Cue[] {
  const parser = new DOMParser();
  const doc = parser.parseFromString(xml, 'text/xml');
  const cues: Cue[] = [];

  const TTML_NS = 'http://www.w3.org/ns/ttml';
  let pTags = doc.getElementsByTagNameNS(TTML_NS, 'p');
  if (pTags.length === 0) {
    pTags = doc.getElementsByTagNameNS('*', 'p');
  }
  if (pTags.length === 0) {
    const all = doc.querySelectorAll('p');
    all.forEach(el => processP(el, cues));
    return cues;
  }

  for (let i = 0; i < pTags.length; i++) {
    processP(pTags[i], cues);
  }

  return cues;
}

function processP(el: Element, cues: Cue[]) {
  const begin = el.getAttribute('begin') || '';
  const end = el.getAttribute('end') || '';
  const dur = el.getAttribute('dur') || '';
  const text = (el.textContent || '').replace(/\s+/g, ' ').trim();
  if (!text || !begin) return;

  const startTime = parseTimestamp(begin);
  let endTime: number;
  if (end) {
    endTime = parseTimestamp(end);
  } else if (dur) {
    endTime = startTime + parseTimestamp(dur);
  } else {
    endTime = startTime + 5;
  }

  cues.push({ start: startTime, end: endTime, text });
}

function parseTimestamp(ts: string): number {
  const parts = ts.split(':');
  if (parts.length === 3) {
    const [h, m, s] = parts;
    return parseInt(h) * 3600 + parseInt(m) * 60 + parseFloat(s);
  }
  if (parts.length === 2) {
    const [m, s] = parts;
    return parseInt(m) * 60 + parseFloat(s);
  }
  return parseFloat(ts);
}

function decodeHTMLEntities(text: string): string {
  const el = document.createElement('textarea');
  el.innerHTML = text;
  return el.value;
}
