import { DEV } from './config';

const PREFIX = '[MajorTom]';

/**
 * Dev builds mirror logs to the local log server (`npm run logs`) so behaviour
 * inside a page can be read without keeping devtools open. Production builds
 * compile all of this away and never touch the network.
 */
function send(level: 'info' | 'warn' | 'error', args: unknown[]) {
  const fn = level === 'error' ? console.error : level === 'warn' ? console.warn : console.log;
  fn(PREFIX, ...args);
  if (!DEV) return;
  try {
    const msg = args
      .map(a => (typeof a === 'string' ? a : (() => { try { return JSON.stringify(a); } catch { return String(a); } })()))
      .join(' ');
    fetch('http://localhost:7777', { method: 'POST', body: `[${level.toUpperCase()}] ${msg}` }).catch(() => {});
  } catch {
    /* logging must never break the page */
  }
}

export const log = {
  info: (...a: unknown[]) => send('info', a),
  warn: (...a: unknown[]) => send('warn', a),
  error: (...a: unknown[]) => send('error', a),
};
