/**
 * Smoke tests for the pure logic: parsing, cue lookup, sentence grouping, and
 * the ARD adapter's URL extraction.
 *
 *   npm run smoke          offline fixtures only
 *   npm run smoke -- --live   also hits the real ARD API (needs network + DE geo)
 *
 * TTML/EBU-TT parsing needs a DOM and is only exercised in the browser.
 */
import {cueIndexAt, detectFormat, parse} from '../src/capture/parsers';
import {groupSentences, nextBatch} from '../src/translate';
import {parseYtPayload, pickArdSubtitleUrl, pickSpokenTrack} from '../src/capture/adapters';

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
{
    // Automatic captions roll: each line stays up into the next one.
    const json = JSON.stringify({
        events: [
            {tStartMs: 11000, dDurationMs: 4799, segs: [{utf8: 'CL Air,'}]},
            {tStartMs: 13320, dDurationMs: 4640, segs: [{utf8: 'willkommen zurück'}]},
        ],
    });
    const cues = parse(json, 'https://youtube.com/api/timedtext?fmt=json3');
    eq('rolling line clipped to the next', cues[0].end, 13.32);
    eq('last line keeps its length', cues[1].end, 17.96);
    eq('newer line shows once it starts', cueIndexAt(cues, 14, 0), 1);
}
{
    // Authored tracks come padded with zero-width spaces.
    const json = JSON.stringify({
        events: [{tStartMs: 0, dDurationMs: 1000, segs: [{utf8: '\u200b\u200b\u200b \u200bEin Fenster.\u200b \u200b\u200b'}]}],
    });
    eq('zero-width spaces stripped', parse(json, 'timedtext')[0].text, 'Ein Fenster.');
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
        v, token: {pot: 'p'}, tracks: [{baseUrl: `https://x/${v}`, languageCode: 'de', kind: 'asr'}],
    });

    eq('matching video id is accepted', parseYtPayload(payload('abc'), 'abc')?.tracks.length, 1);
    // The bug this guards: YouTube changes the URL before refreshing the payload,
    // so an unchecked read serves the previous video's subtitles.
    eq('stale payload is rejected', parseYtPayload(payload('old'), 'new'), null);
    eq('missing attribute', parseYtPayload(null, 'abc'), null);
    eq('malformed json', parseYtPayload('{not json', 'abc'), null);
    eq('unstamped payload still usable',
        parseYtPayload(JSON.stringify({tracks: [{baseUrl: 'u', languageCode: 'de'}]}), 'abc')?.tracks.length, 1);
    eq('no id in url falls through', parseYtPayload(payload('abc'), null)?.tracks.length, 1);
    eq('tracks missing', parseYtPayload(JSON.stringify({v: 'abc'}), 'abc')?.tracks.length, 0);
    eq('token carried', parseYtPayload(payload('abc'), 'abc')?.token?.pot, 'p');
    eq('no token yet', parseYtPayload(JSON.stringify({v: 'abc', tracks: []}), 'abc')?.token, null);
}

console.log('\nYouTube track choice');
{
    const t = (languageCode: string, kind?: string) => ({baseUrl: `u/${languageCode}/${kind}`, languageCode, kind});
    const pick = (tracks: ReturnType<typeof t>[], audio = '', learning = 'de') =>
        pickSpokenTrack({v: 'x', token: {}, audio, tracks}, learning)?.baseUrl;

    // A German podcast: only the automatic transcript.
    eq('lone transcript', pick([t('de', 'asr')]), 'u/de/asr');
    // The old rule took the first authored track, whatever its language.
    eq('spoken language beats first authored',
        pick([t('ar'), t('en'), t('de'), t('en', 'asr')]), 'u/en/undefined');
    eq('authored beats transcript in same language', pick([t('de', 'asr'), t('de')]), 'u/de/undefined');
    eq('German dub kept → German track', pick([t('en'), t('de'), t('en', 'asr')], 'de'), 'u/de/undefined');
    eq('single-track audio is ignored', pick([t('fr'), t('de', 'asr')], 'und'), 'u/de/asr');
    eq('no transcript → learning language', pick([t('fr'), t('de')]), 'u/de/undefined');
    eq('nothing matches → first', pick([t('fr'), t('it')]), 'u/fr/undefined');
}

/* ── Translation order ────────────────────────────────────────────────────── */

console.log('\nPlayhead-first batching');
{
    const cues = Array.from({length: 10}, (_, i) => ({start: i * 10, end: i * 10 + 5, text: `s${i}.`}));
    const {cueGroup} = groupSentences(cues);
    const none = new Array(10).fill(false);

    eq('starts at the line playing', nextBatch(none, cueGroup, cues, 42, 3).join(), '4,5,6');
    eq('between lines → the next one', nextBatch(none, cueGroup, cues, 47, 2).join(), '5,6');
    eq('stops at a finished sentence',
        nextBatch(none.map((_, i) => i === 6), cueGroup, cues, 42, 5).join(), '4,5');
    eq('wraps to the start when the rest is done',
        nextBatch(none.map((_, i) => i >= 3), cueGroup, cues, 42, 5).join(), '0,1,2');
    eq('all done → nothing', nextBatch(new Array(10).fill(true), cueGroup, cues, 0, 5).length, 0);
    eq('capped by length', nextBatch(none, cueGroup, cues, 0, 10, new Array(10).fill(600), 1500).join(), '0,1');
    eq('one long sentence still goes', nextBatch(none, cueGroup, cues, 0, 10, new Array(10).fill(5000), 1500).join(), '0');
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
