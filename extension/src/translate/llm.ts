/**
 * The local model: any OpenAI-compatible server, llama-server by default.
 * Runs in the service worker, whose host permissions reach localhost.
 *
 * Mirrors the desktop app's `ModelTranslator` (transcriber/mac CallCore): same
 * endpoint, same constrained-JSON approach, same fallback for servers that do
 * not take a schema.
 */
import {getSettings} from '../shared/storage';
import {Gloss} from '../shared/types';

/** Resolved once per endpoint, so the list is not fetched for every batch. */
let listed: { endpoint: string; model: string } | null = null;

async function modelFor(endpoint: string, configured: string): Promise<string> {
    if (configured) return configured;
    if (listed?.endpoint === endpoint) return listed.model;
    const res = await reach(`${endpoint}/models`, {signal: AbortSignal.timeout(8000)});
    if (!res.ok) throw new Error(`the model server answered ${res.status}`);
    const json = await res.json() as { data?: Array<{ id: string }> };
    const id = json.data?.[0]?.id;
    if (!id) throw new Error('the model server lists no models');
    listed = {endpoint, model: id};
    return id;
}

/** Turns "connection refused" into something that says what to do. */
async function reach(url: string, init: RequestInit): Promise<Response> {
    try {
        return await fetch(url, init);
    } catch (e) {
        if ((e as Error)?.name === 'TimeoutError') throw new Error('the local model took too long to answer');
        throw new Error(`the local model is not running at ${url.replace(/\/(models|chat\/completions)$/, '')}`);
    }
}

export async function modelName(): Promise<string> {
    const s = await getSettings();
    return modelFor(s.llmEndpoint.replace(/\/+$/, ''), s.llmModel.trim());
}

/** One structured request. Returns the parsed JSON object the model produced. */
async function ask(system: string, user: string, schema: object, maxTokens: number): Promise<any> {
    const s = await getSettings();
    const endpoint = s.llmEndpoint.replace(/\/+$/, '');
    const body: Record<string, unknown> = {
        model: await modelFor(endpoint, s.llmModel.trim()),
        temperature: 0.2,
        max_tokens: maxTokens,
        // Thinking costs ten times the tokens for no visible gain here: on
        // Gemma 4, a 14-line batch took 2,760 tokens with it and 270 without,
        // and the translations were near-identical.
        reasoning_effort: 'none',
        messages: [{role: 'system', content: system}, {role: 'user', content: user}],
        // Constrained decoding, so the reply is always parseable and always
        // has exactly as many lines as we sent.
        response_format: {type: 'json_schema', json_schema: {name: 'answer', strict: true, schema}},
    };

    const post = () => reach(`${endpoint}/chat/completions`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify(body),
        // A cold llama-server loads the model before it answers at all.
        signal: AbortSignal.timeout(180_000),
    });

    let res = await post();
    if (res.status >= 400 && res.status < 500) {
        const detail = await res.text().catch(() => '');
        // Not every server takes a JSON schema; ask again and dig the JSON out.
        if (!/response_format|json_schema|schema/i.test(detail)) {
            throw new Error(`the model server answered ${res.status}: ${detail.slice(0, 160)}`);
        }
        delete body.response_format;
        res = await post();
    }
    if (!res.ok) throw new Error(`the model server answered ${res.status}`);

    const json = await res.json() as {
        choices?: Array<{ message?: { content?: string; reasoning_content?: string } }>
    };
    const msg = json.choices?.[0]?.message;
    // A reasoning model that runs out of room leaves its answer in the thinking.
    const text = msg?.content || msg?.reasoning_content || '';
    return extractJson(text);
}

function extractJson(text: string): any {
    try {
        return JSON.parse(text);
    } catch {
        const start = text.indexOf('{'), end = text.lastIndexOf('}');
        if (start >= 0 && end > start) {
            try {
                return JSON.parse(text.slice(start, end + 1));
            } catch { /* fall through */
            }
        }
        throw new Error('the model did not return JSON');
    }
}

const names = new Intl.DisplayNames(['en'], {type: 'language'});

/** 'DE' → German, 'EN-US' → English, '' → '' (unknown). */
export function languageName(code: string): string {
    const base = (code || '').split('-')[0].toLowerCase();
    if (!base) return '';
    try {
        return names.of(base) || base;
    } catch {
        return base;
    }
}

/* ── Subtitles ────────────────────────────────────────────────────────────── */

function subsPrompt(source: string, target: string): string {
    const from = source ? `${source} ` : '';
    return `You translate ${from}video subtitles into natural ${target} for someone learning ${source || 'the language'} at an upper-intermediate level.
You get numbered sentences from one video, in order. Give one ${target} translation for each, in the same order.
Translate the meaning, not word for word, the way a native ${target} speaker would say it.
A sentence may be a fragment that continues in the next one; translate each so the pieces read naturally in sequence.
Automatic captions have no punctuation and some misheard words; translate what was most likely said.
Lines marked as context come just before; use them to understand the sentences but do not translate them.`;
}

/**
 * Translate a batch of subtitle sentences. `context` is the few sentences
 * before the batch, sent so a batch that starts mid-conversation still knows
 * who "she" is.
 */
export async function translateSubs(
    lines: string[], context: string[], source: string, target: string,
): Promise<string[]> {
    const from = languageName(source), to = languageName(target) || 'English';
    const user = [
        ...(context.length ? ['Context:', ...context.map(c => `  ${c}`), ''] : []),
        'Translate:',
        ...lines.map((l, i) => `${i + 1}. ${l}`),
    ].join('\n');

    const field = `${to.toLowerCase().replace(/\W+/g, '_')}_translations`;
    const schema = {
        type: 'object',
        properties: {
            [field]: {type: 'array', items: {type: 'string'}, minItems: lines.length, maxItems: lines.length},
        },
        required: [field],
        additionalProperties: false,
    };

    // About three characters a token, so one token per source character
    // leaves room for the translation and the JSON around it.
    const budget = 200 + lines.reduce((n, l) => n + l.length, 0);
    const out = await ask(subsPrompt(from, to), user, schema, budget);
    const list: unknown = out?.[field] ?? Object.values(out ?? {})[0];
    if (!Array.isArray(list) || list.length !== lines.length) {
        throw new Error(`the model returned ${Array.isArray(list) ? list.length : 0} lines for ${lines.length}`);
    }
    // Models sometimes echo the numbering back.
    return list.map(t => String(t ?? '').replace(/^\s*\d+[.)]\s*/, '').trim());
}

/* ── Clicked words ────────────────────────────────────────────────────────── */

function glossPrompt(source: string, target: string, field: string): string {
    return `You help someone learning ${source || 'a language'}. You are given a word and the subtitle line it appeared in.
\`dictionary_form\` is the form you would look the word up under: the infinitive for a verb (joined with a separable prefix that sits elsewhere in the line), the nominative singular with its article for a noun.
\`${field}\` is a short ${target} gloss of the sense used in this line, not every sense. If the word only makes sense here as part of a fixed expression, gloss the expression.`;
}

export async function gloss(word: string, sentence: string, source: string, target: string): Promise<Gloss> {
    const from = languageName(source), to = languageName(target) || 'English';
    const field = `${to.toLowerCase().replace(/\W+/g, '_')}_meaning`;
    const schema = {
        type: 'object',
        properties: {dictionary_form: {type: 'string'}, [field]: {type: 'string'}},
        required: ['dictionary_form', field],
        additionalProperties: false,
    };
    const out = await ask(glossPrompt(from, to, field), `word: ${word}\nsentence: ${sentence}`, schema, 200);
    const meaning = String(out?.[field] ?? '').replace(/\s+/g, ' ').trim();
    if (!meaning) throw new Error('the model returned no meaning');
    // A gloss is a few words; a paragraph means it ignored the instruction.
    if (meaning.length > 300) throw new Error('the model returned a paragraph, not a gloss');
    return {form: String(out?.dictionary_form ?? '').trim() || word, meaning};
}
