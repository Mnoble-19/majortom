const cache = new Map<string, string>();

export async function translate(text: string, from: string, to: string): Promise<string> {
  if (!text.trim() || from === to) return text;
  const key = `${from}:${to}:${text}`;
  if (cache.has(key)) return cache.get(key)!;

  try {
    const resp = await fetch(
      `https://translate.googleapis.com/translate_a/single?client=gtx&sl=${from}&tl=${to}&dt=t&q=${encodeURIComponent(text)}`
    );
    const data = await resp.json();
    const result = data[0].map((s: any) => s[0]).join('');
    cache.set(key, result);
    return result;
  } catch {
    return '';
  }
}
