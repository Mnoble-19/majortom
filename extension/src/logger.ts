const LOG_URL = 'http://localhost:7777';

function send(level: string, ...args: any[]) {
  const msg = args.map(a => (typeof a === 'string' ? a : JSON.stringify(a))).join(' ');
  const prefix = `[MajorTom:${level}]`;
  // Always log to browser console
  if (level === 'error') console.error(prefix, msg);
  else if (level === 'warn') console.warn(prefix, msg);
  else console.log(prefix, msg);
  // Best-effort send to local log server
  fetch(LOG_URL, { method: 'POST', body: `[${level.toUpperCase()}] ${msg}` }).catch(() => {});
}

export const log = {
  info:  (...args: any[]) => send('info',  ...args),
  warn:  (...args: any[]) => send('warn',  ...args),
  error: (...args: any[]) => send('error', ...args),
};
