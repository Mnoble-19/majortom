/**
 * Runs in the page's own JS world at document_start (see manifest `world:
 * "MAIN"`). It exists to see things the isolated content-script world cannot:
 * page globals, native TextTracks, and network responses.
 *
 * Deliberately dependency-free — no chrome.* APIs are available here, and
 * anything it throws would be a page error, so everything is defensive.
 */
(() => {
    if ((window as any).__majortomInjected) return;
    (window as any).__majortomInjected = true;

    type Pending = { kind: 'sub-file'; url: string; body: string };

    let active = false;
    let hideNative = true;
    /** True while the content script still has no cues, enabling body sniffing. */
    let hungry = true;
    const pending: Pending[] = [];
    const MAX_PENDING = 25;

    function post(msg: Record<string, unknown>) {
        try {
            window.postMessage({src: 'majortom', ...msg}, '*');
        } catch { /* ignore */
        }
    }

    function emitSubFile(url: string, body: string) {
        if (!body || body.length < 20) return;
        if (!active) {
            // Captured before the content script configured us — hold it briefly.
            if (pending.length < MAX_PENDING) pending.push({kind: 'sub-file', url, body});
            return;
        }
        post({kind: 'sub-file', url, body});
    }

    window.addEventListener('message', e => {
        const d = e.data;
        if (e.source !== window || !d || d.src !== 'majortom-cfg') return;
        active = !!d.active;
        hideNative = !!d.hideNative;
        hungry = d.hungry !== false;
        if (active) {
            while (pending.length) {
                const p = pending.shift()!;
                post({kind: 'sub-file', url: p.url, body: p.body});
            }
            scanVideos();
        } else {
            pending.length = 0;
        }
    });

    /* ── YouTube player response ────────────────────────────────────────────── */

    /**
     * Copied onto a DOM attribute rather than posted, so the content script can
     * read it synchronously whenever it likes instead of racing a message.
     */
    function exposeYouTubeTracks() {
        try {
            const pr = (window as any).ytInitialPlayerResponse
                || (window as any).ytplayer?.config?.args?.raw_player_response;
            const tracks = pr?.captions?.playerCaptionsTracklistRenderer?.captionTracks;
            if (!Array.isArray(tracks) || tracks.length === 0) return;

            // Stamped with the video id: YouTube swaps pages faster than it refreshes
            // this object, and un-stamped data would load the previous video's track.
            document.documentElement.setAttribute('data-majortom-yt', JSON.stringify({
                v: pr?.videoDetails?.videoId || '',
                tracks: tracks.map((t: any) => ({
                    baseUrl: t.baseUrl,
                    languageCode: t.languageCode,
                    name: t.name?.simpleText || t.name?.runs?.[0]?.text || t.languageCode,
                    kind: t.kind,
                })),
            }));
            const title = pr?.videoDetails?.title;
            if (title) post({kind: 'media-meta', title});
        } catch { /* ignore */
        }
    }

    if (location.hostname.endsWith('youtube.com')) {
        // Drop stale data the instant navigation starts, then republish once the
        // new player response has landed.
        const refresh = () => {
            document.documentElement.removeAttribute('data-majortom-yt');
            exposeYouTubeTracks();
            for (const delay of [400, 900, 1800]) setTimeout(exposeYouTubeTracks, delay);
        };

        exposeYouTubeTracks();
        document.addEventListener('readystatechange', exposeYouTubeTracks);
        window.addEventListener('yt-navigate-start', refresh);
        window.addEventListener('yt-navigate-finish', refresh);
        const push = history.pushState;
        history.pushState = function (...args: Parameters<typeof history.pushState>) {
            const r = push.apply(this, args);
            refresh();
            return r;
        };
    }

    /* ── Native TextTracks ──────────────────────────────────────────────────── */

    const seenTracks = new WeakSet<TextTrack>();
    const trackSizes = new WeakMap<TextTrack, number>();
    let trackSeq = 0;

    function cueText(cue: TextTrackCue): string {
        const raw = (cue as VTTCue).text ?? '';
        return String(raw).replace(/<[^>]*>/g, '').trim();
    }

    function emitTrack(track: TextTrack, id: string) {
        const list = track.cues;
        if (!list || list.length === 0) return;
        if (trackSizes.get(track) === list.length) return; // nothing new
        trackSizes.set(track, list.length);

        const cues: Array<{ start: number; end: number; text: string }> = [];
        for (let i = 0; i < list.length; i++) {
            const c = list[i];
            const text = cueText(c);
            if (text) cues.push({start: c.startTime, end: c.endTime, text});
        }
        if (cues.length === 0) return;

        post({
            kind: 'track-cues',
            trackId: id,
            lang: track.language || '',
            label: track.label || track.language || 'track',
            cues,
        });
    }

    function attachTrack(track: TextTrack) {
        if (seenTracks.has(track)) return;
        if (track.kind !== 'subtitles' && track.kind !== 'captions') return;
        seenTracks.add(track);
        const id = `tt-${++trackSeq}`;

        // 'hidden' populates .cues without the browser drawing them — exactly what
        // we want, since we render our own line.
        try {
            if (track.mode === 'disabled') track.mode = 'hidden';
            else if (track.mode === 'showing' && hideNative) track.mode = 'hidden';
        } catch { /* some players lock this */
        }

        track.addEventListener('cuechange', () => emitTrack(track, id));
        // Streaming players append cues over time and fire no event for it.
        const poll = setInterval(() => emitTrack(track, id), 1500);
        setTimeout(() => clearInterval(poll), 10 * 60 * 1000);
        emitTrack(track, id);
    }

    const seenVideos = new WeakSet<HTMLVideoElement>();

    function scanVideos() {
        if (!active) return;
        for (const v of Array.from(document.querySelectorAll('video'))) {
            const tt = (v as HTMLVideoElement).textTracks;
            if (!tt) continue;
            for (let i = 0; i < tt.length; i++) attachTrack(tt[i]);
            if (!seenVideos.has(v as HTMLVideoElement)) {
                seenVideos.add(v as HTMLVideoElement);
                tt.addEventListener('addtrack', (e: TrackEvent) => {
                    if (e.track && (e.track as TextTrack).kind !== undefined) attachTrack(e.track as TextTrack);
                });
            }
        }
    }

    setInterval(scanVideos, 2000);

    /* ── Network sniffing ───────────────────────────────────────────────────── */

    const SUB_URL = /\.(vtt|srt|ttml|dfxp|xml)(\?|#|$)|timedtext|subtitle|caption|ebutt|webvtt/i;
    const SUB_TYPE = /text\/vtt|application\/ttml|application\/x-subrip|text\/xml|application\/xml/i;
    const NOISE = /doubleclick|google-analytics|googlevideo\.com\/videoplayback|\.ts(\?|$)|\.m4s(\?|$)|\.mp4(\?|$)|\.aac(\?|$)|sand-hub|\/log(_|\?)/i;

    function interesting(url: string, contentType?: string | null): boolean {
        if (!url || NOISE.test(url)) return false;
        if (SUB_URL.test(url)) return true;
        return !!contentType && SUB_TYPE.test(contentType);
    }

    /**
     * Some players fetch subtitles from opaque URLs with a generic content type,
     * so the URL tells us nothing. While we still have no cues, fall back to
     * sniffing the body itself. Requires a declared text-ish content type so we
     * never buffer an unbounded stream.
     */
    function worthSniffing(res: Response): boolean {
        if (!hungry) return false;
        const ct = res.headers.get('content-type');
        if (!ct || !/text|json|xml/i.test(ct)) return false;
        const len = Number(res.headers.get('content-length') || 0);
        return len > 0 && len <= 4 * 1024 * 1024;
    }

    function looksLikeSubtitles(body: string): boolean {
        const head = body.slice(0, 300).trimStart();
        if (!head) return false;
        if (head.startsWith('WEBVTT')) return true;
        if (/^<(\?xml|tt[\s>]|tt:tt)/i.test(head)) return true;
        if (/^\d+\s*\r?\n\d{2}:\d{2}:\d{2}[,.]\d{3}\s*-->/.test(head)) return true;
        return head.includes('-->') && /\d{2}:\d{2}/.test(head);
    }

    const origFetch = window.fetch;
    window.fetch = function (input: RequestInfo | URL) {
        const url = typeof input === 'string' ? input
            : input instanceof URL ? input.href
                : (input as Request)?.url || '';
        const p = origFetch.apply(this, arguments as any);

        if (url && !NOISE.test(url)) {
            p.then((res: Response) => {
                if (!res.ok) return;
                if (interesting(url, res.headers.get('content-type'))) {
                    res.clone().text().then(t => emitSubFile(url, t)).catch(() => {
                    });
                } else if (worthSniffing(res)) {
                    res.clone().text()
                        .then(t => {
                            if (looksLikeSubtitles(t)) emitSubFile(url, t);
                        })
                        .catch(() => {
                        });
                }
            }).catch(() => {
            });
        }
        return p;
    };

    const OrigXHR = window.XMLHttpRequest;

    function PatchedXHR(this: any) {
        const xhr = new OrigXHR();
        let url = '';
        const open = xhr.open;
        xhr.open = function (_method: string, u: string | URL) {
            url = String(u);
            return open.apply(xhr, arguments as any);
        };
        xhr.addEventListener('load', () => {
            try {
                // responseText throws for non-text responseTypes — check before reading.
                if (xhr.responseType && xhr.responseType !== 'text') return;
                const ct = xhr.getResponseHeader('content-type');
                if (interesting(url, ct)) {
                    emitSubFile(url, xhr.responseText || '');
                } else if (hungry && ct && /text|json|xml/i.test(ct)) {
                    const body = xhr.responseText || '';
                    if (body.length <= 4 * 1024 * 1024 && looksLikeSubtitles(body)) emitSubFile(url, body);
                }
            } catch { /* ignore */
            }
        });
        return xhr;
    }

    PatchedXHR.prototype = OrigXHR.prototype;
    Object.setPrototypeOf(PatchedXHR, OrigXHR);
    (window as any).XMLHttpRequest = PatchedXHR;
})();
