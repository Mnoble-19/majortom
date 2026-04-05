import { Cue } from './types';

export function parseYouTubeXML(xml: string): Cue[] {
  const parser = new DOMParser();
  const doc = parser.parseFromString(xml, 'text/xml');
  const cues: Cue[] = [];

  const texts = doc.querySelectorAll('text');
  texts.forEach(el => {
    const start = parseFloat(el.getAttribute('start') || '0');
    const dur = parseFloat(el.getAttribute('dur') || '0');
    cues.push({
      start,
      end: start + dur,
      text: decodeHTMLEntities(el.textContent || ''),
    });
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
