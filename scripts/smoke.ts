/**
 * Smoke tests for the pure logic: parsing, cue lookup, sentence grouping, and
 * the ARD adapter's URL extraction.
 *
 *   npm run smoke          offline fixtures only
 *   npm run smoke -- --live   also hits the real ARD API (needs network + DE geo)
 *
 * TTML/EBU-TT parsing needs a DOM and is only exercised in the browser.
 */
import {cueIndexAt, detectFormat, parse} from '../extension/src/capture/parsers';
import {groupSentences} from '../extension/src/translate';
import {parseYtPayload, pickArdSubtitleUrl} from '../extension/src/capture/adapters';

let failures = 0;

function check(name: string, cond: boolean, detail = '') {
    if (cond) {
        console.log(`  ok   ${name}`);
    } else {
        failures++;
        console.log(`  FAIL ${name}${detail ? ` — ${detail}` : ''}`);
    }
}

function eq<T>(name: string, actual: T, expected: T) {
    check(name, Object.is(actual, expected), `got ${JSON.stringify(actual)}, want ${JSON.stringify(expected)}`);
}

/* ── WebVTT ───────────────────────────────────────────────────────────────── */

console.log('\nWebVTT');
{
    // Shaped like a real ARD file: cue settings after the end time, styling tags,
    // a filler "." cue, and a line held across two consecutive cues.
    const vtt = `WEBVTT

1
00:00:00.000 --> 00:00:01.000 align:middle
<c.textWhite>.</c>

2
00:00:01.080 --> 00:00:02.920 align:middle
<c.textWhite>Untertitelung: BR 2026</c>

3
00:00:03.000 --> 00:00:04.960 align:middle
<c.textWhite>Sie alle verdienen Geld</c>
<c.textWhite>mit Vorhersagen.</c>

4
00:00:04.960 --> 00:00:06.000 align:middle
<c.textWhite>Sie alle verdienen Geld
mit Vorhersagen.</c>

5
00:00:09.880 --> 00:00:11.680 align:middle
Aber was ist das?
`;
    const cues = parse(vtt, 'x.vtt');
    eq('format detected', detectFormat(vtt), 'vtt');
    eq('junk "." cue dropped', cues.some(c => c.text === '.'), false);
    eq('styling tags stripped', cues.some(c => c.text.includes('<c.')), false);
    eq('cue count after merge', cues.length, 3);
    eq('duplicate held line merged', cues[1].end, 6);
    eq('multi-line cue joined', cues[1].text, 'Sie alle verdienen Geld\nmit Vorhersagen.');
    eq('timestamps parsed', cues[2].start, 9.88);
    eq('cue settings not parsed as time', cues[2].end, 11.68);
}

console.log('\nSRT');
{
    const srt = `1
00:00:02,500 --> 00:00:04,000
Hallo Welt

2
00:00:05,000 --> 00:00:06,250
Zweite Zeile
`;
    const cues = parse(srt, 'x.srt');
    eq('srt cue count', cues.length, 2);
    eq('comma decimals', cues[0].start, 2.5);
    eq('second cue end', cues[1].end, 6.25);
}

console.log('\nYouTube json3');
{
    const json = JSON.stringify({
        events: [
            {tStartMs: 1000, dDurationMs: 2000, segs: [{utf8: 'Hallo '}, {utf8: 'Welt'}]},
            {tStartMs: 3000, dDurationMs: 1000, segs: [{utf8: '\n'}]},
            {tStartMs: 4000, dDurationMs: 1500, segs: [{utf8: 'Wie gehts?'}]},
        ],
    });
    const cues = parse(json, 'https://youtube.com/api/timedtext?fmt=json3');
    eq('segments joined', cues[0].text, 'Hallo Welt');
    eq('blank event dropped', cues.length, 2);
    eq('ms converted to seconds', cues[0].end, 3);
}

/* ── Cue lookup ───────────────────────────────────────────────────────────── */

console.log('\ncueIndexAt');
{
    const cues = [
        {start: 0, end: 2, text: 'a'},
        {start: 2.5, end: 4, text: 'b'},
        {start: 10, end: 12, text: 'c'},
    ];
    eq('inside first', cueIndexAt(cues, 1), 0);
    eq('inside second', cueIndexAt(cues, 3), 1);
    eq('in the gap', cueIndexAt(cues, 2.2), -1);
    eq('after the end', cueIndexAt(cues, 99), -1);
    eq('before the start', cueIndexAt(cues, -1), -1);
    eq('exact boundary', cueIndexAt(cues, 2), 0);
    eq('stale hint still correct', cueIndexAt(cues, 11, 0), 2);
    eq('empty list', cueIndexAt([], 5), -1);
}

/* ── Sentence grouping ────────────────────────────────────────────────────── */

console.log('\ngroupSentences');
{
    const cues = [
        {start: 0, end: 1, text: 'Sie alle verdienen Geld'},
        {start: 1, end: 2, text: 'mit Vorhersagen.'},
        {start: 2, end: 3, text: 'Aber was ist das?'},
        {start: 30, end: 31, text: 'Ein neuer Absatz'},
    ];
    const g = groupSentences(cues);
    eq('fragments joined into a sentence', g.texts[0], 'Sie alle verdienen Geld mit Vorhersagen.');
    eq('both cues map to one group', g.cueGroup[0] === g.cueGroup[1], true);
    eq('new sentence is its own group', g.texts[1], 'Aber was ist das?');
    eq('large time gap splits', g.texts[2], 'Ein neuer Absatz');
    eq('every cue is mapped', g.cueGroup.length, cues.length);
    eq('no group index is out of range', g.cueGroup.every(i => i < g.texts.length), true);
}

/* ── ARD adapter ──────────────────────────────────────────────────────────── */

console.log('\nARD subtitle URL extraction');
{
    const payload = {
        widgets: [{
            mediaCollection: {
                embedded: {
                    subtitles: [{
                        sources: [
                            {
                                kind: 'ebutt',
                                url: 'https://api.ardmediathek.de/player-service/subtitle/ebutt/urn:ard:subtitle:abc'
                            },
                            {
                                kind: 'webvtt',
                                url: 'https://api.ardmediathek.de/player-service/subtitle/webvtt/urn:ard:subtitle:abc.vtt'
                            },
                        ],
                    }],
                },
            },
        }],
    };
    eq('prefers webvtt over ebutt',
        pickArdSubtitleUrl(payload),
        'https://api.ardmediathek.de/player-service/subtitle/webvtt/urn:ard:subtitle:abc.vtt');
    eq('falls back to ebutt',
        pickArdSubtitleUrl({a: {url: 'https://x/player-service/subtitle/ebutt/urn:ard:subtitle:z'}}),
        'https://x/player-service/subtitle/ebutt/urn:ard:subtitle:z');
    eq('null when absent', pickArdSubtitleUrl({nothing: 'here'}), null);
    eq('survives odd shapes', pickArdSubtitleUrl([null, 1, 'str', {a: [undefined]}]), null);
}

/* ── YouTube track payload ────────────────────────────────────────────────── */

console.log('\nYouTube stale-payload guard');
{
    const payload = (v: string) => JSON.stringify({
        v, tracks: [{baseUrl: `https://x/${v}`, languageCode: 'de', kind: 'asr'}],
    });

    eq('matching video id is accepted', parseYtPayload(payload('abc'), 'abc').length, 1);
    // The bug this guards: YouTube changes the URL before refreshing the payload,
    // so an unchecked read serves the previous video's subtitles.
    eq('stale payload is rejected', parseYtPayload(payload('old'), 'new').length, 0);
    eq('missing attribute', parseYtPayload(null, 'abc').length, 0);
    eq('malformed json', parseYtPayload('{not json', 'abc').length, 0);
    eq('unstamped payload still usable',
        parseYtPayload(JSON.stringify({tracks: [{baseUrl: 'u', languageCode: 'de'}]}), 'abc').length, 1);
    eq('no id in url falls through', parseYtPayload(payload('abc'), null).length, 1);
    eq('tracks missing', parseYtPayload(JSON.stringify({v: 'abc'}), 'abc').length, 0);
}

/* ── Live ARD (opt-in) ────────────────────────────────────────────────────── */

if (process.argv.includes('--live')) {
    console.log('\nLive ARD API');
    const id = 'Y3JpZDovL2JyLmRlL2Jyb2FkY2FzdC9GMjAyNldPMDAxNjAzQTA';
    try {
        const api = `https://api.ardmediathek.de/page-gateway/pages/ard/item/${id}?embedded=false&mcV6=true`;
        const meta = await fetch(api);
        check('item metadata reachable', meta.ok, `HTTP ${meta.status}`);

        const url = pickArdSubtitleUrl(await meta.json());
        check('subtitle url found in live payload', !!url, 'none matched');

        if (url) {
            const res = await fetch(url);
            const body = await res.text();
            check('subtitle file fetched', res.ok && body.length > 1000, `${res.status}, ${body.length} bytes`);

            const cues = parse(body, url);
            check('live file parses', cues.length > 50, `${cues.length} cues`);
            check('cues are ordered', cues.every((c, i) => i === 0 || c.start >= cues[i - 1].start));
            check('cues have text', cues.every(c => c.text.trim().length > 0));
            check('no markup leaked through', !cues.some(c => /<[^>]+>/.test(c.text)));
            console.log(`       ${cues.length} cues, first: "${cues[0]?.text.slice(0, 60)}"`);
        }
    } catch (e) {
        check('live ARD check', false, (e as Error).message);
    }
}

console.log(failures === 0 ? '\nAll checks passed.\n' : `\n${failures} check(s) failed.\n`);
process.exit(failures === 0 ? 0 : 1);
