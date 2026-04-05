const LOG_URL = 'http://localhost:7777';

function send(level: string, ...args: any[]) {
  const msg = args.map(a => typeof a === 'string' ? a : JSON.stringify(a)).join(' ');
  const line = `[${level}] ${msg}`;
  console[level === 'error' ? 'error' : 'log'](`[MajorTom] ${msg}`);
  fetch(LOG_URL, { method: 'POST', body: line }).catch(() => {});
}

export const log = {
  info: (...args: any[]) => send('info', ...args),
  error: (...args: any[]) => send('error', ...args),
  warn: (...args: any[]) => send('warn', ...args),
};
