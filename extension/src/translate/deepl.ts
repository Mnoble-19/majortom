/**
 * DeepL provider. Runs in the service worker, because translation needs the
 * extension's host permissions rather than the page's origin.
 *
 * A local-model provider would sit beside this file and expose the same shape.
 */

/** Free keys are suffixed `:fx` and live on a different host to Pro keys. */
function endpoint(key: string): string {
    return key.trim().endsWith(':fx')
        ? 'https://api-free.deepl.com/v2/translate'
        : 'https://api.deepl.com/v2/translate';
}

export async function translate(
    texts: string[], source: string, target: string, key: string,
): Promise<string[]> {
    const body: Record<string, unknown> = {
        text: texts,
        target_lang: target,
        preserve_formatting: true,
    };
    // Omitting source_lang lets DeepL auto-detect, which is what '' means here.
    if (source) body.source_lang = source;

    const res = await fetch(endpoint(key), {
        method: 'POST',
        headers: {
            'Authorization': `DeepL-Auth-Key ${key.trim()}`,
            'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
    });

    if (!res.ok) {
        const detail = await res.text().catch(() => '');
        // These three are the ones worth explaining in the UI.
        if (res.status === 403) throw new Error('DeepL rejected the API key (403)');
        if (res.status === 456) throw new Error('DeepL quota exhausted for this billing period (456)');
        if (res.status === 429) throw new Error('DeepL rate limit hit (429) — try again shortly');
        throw new Error(`DeepL ${res.status}: ${detail.slice(0, 160)}`);
    }

    const json = await res.json() as { translations?: Array<{ text: string }> };
    return (json.translations || []).map(t => t.text);
}
