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
        if (d.learning) learning = String(d.learning).toLowerCase();
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

    /* ── YouTube ────────────────────────────────────────────────────────────── */

    const isYouTube = location.hostname.endsWith('youtube.com');

    /**
     * YouTube answers a caption request with an empty 200 unless it carries a
     * proof-of-origin token (`pot`) that only the player can mint. So we let
     * the player make one caption request, keep its token, and add it to the
     * track URLs we fetch ourselves. The token is per video; one covers every
     * track of that video.
     */
    const tokens = new Map<string, Record<string, string>>();
    const TOKEN_PARAMS = ['pot', 'potc', 'c', 'cver'];

    /** True for the player's own caption requests, which we never treat as a file. */
    function isYtTimedtext(url: string): boolean {
        return isYouTube && url.includes('/api/timedtext');
    }

    function noteYtToken(url: string) {
        try {
            const u = new URL(url, location.origin);
            const v = u.searchParams.get('v');
            if (!v || !u.searchParams.get('pot') || tokens.has(v)) return;
            const params: Record<string, string> = {};
            for (const k of TOKEN_PARAMS) {
                const val = u.searchParams.get(k);
                if (val) params[k] = val;
            }
            tokens.set(v, params);
            exposeYouTube();
        } catch { /* ignore */
        }
    }

    function ytPlayer(): any {
        return document.getElementById('movie_player');
    }

    /** The minified audio-track object keeps its readable fields one level down. */
    function audioInfo(track: any): { id: string; isDefault?: boolean } | null {
        if (!track) return null;
        for (const k of Object.keys(track)) {
            const v = track[k];
            if (v && typeof v === 'object' && !Array.isArray(v) && 'isDefault' in v && 'id' in v) return v;
        }
        return null;
    }

    /**
     * The track id is `itag;<base64 protobuf>`, and that protobuf names the
     * track's kind: `original`, `dubbed` or `dubbed-auto`.
     */
    function audioKind(track: any): string {
        try {
            const b64 = String(track.id).split(';')[1] || '';
            const raw = atob(b64.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((b64.length + 3) % 4));
            return raw.match(/acont\x12.([a-z-]+)/)?.[1] || '';
        } catch {
            return '';
        }
    }

    const langOf = (track: any) => (audioInfo(track)?.id || '').split('.')[0].split('-')[0].toLowerCase();

    /** What we are told by the content script: the language being learned. */
    let learning = 'de';
    const audioChecked = new Set<string>();

    /**
     * YouTube dubs videos into your interface language, so a German video
     * can start playing in English. Put it back to the original, unless the
     * dub is in the language being learned — then it is exactly what you want.
     */
    function keepOriginalAudio(p: any, v: string) {
        if (audioChecked.has(v)) return;
        const list: any[] = p.getAvailableAudioTracks?.() || [];
        if (list.length < 2) {
            // The list fills in a moment after the video loads.
            if (p.getPlayerState?.() === 1) audioChecked.add(v);
            return;
        }
        audioChecked.add(v);
        const current = p.getAudioTrack?.();
        if (audioKind(current) === 'original' || langOf(current) === learning) return;
        const original = list.find(t => audioKind(t) === 'original')
            || list.find(t => audioInfo(t)?.isDefault);
        if (original && audioInfo(original)?.id !== audioInfo(current)?.id) p.setAudioTrack(original);
    }

    /** How often, and when last, we switched captions on for each video. */
    const forced = new Map<string, { tries: number; at: number }>();

    /**
     * The player only asks for captions while they are switched on. Switch
     * them on long enough to see a request, then back off if they were off —
     * our overlay hides YouTube's own rendering anyway.
     */
    function provokeCaptionRequest(p: any, v: string) {
        if (tokens.has(v)) return;
        // Not before the player has started, when it has no caption module yet.
        if (p.getVideoData?.()?.video_id !== v || p.getPlayerState?.() === -1) return;
        let last = forced.get(v);
        if (!last && p.isSubtitlesOn?.()) {
            // Captions already on: the player is about to ask by itself.
            last = {tries: 0, at: Date.now()};
            forced.set(v, last);
        }
        last ||= {tries: 0, at: 0};
        if (last.tries >= 4 || Date.now() - last.at < 4000) return;
        forced.set(v, {tries: last.tries + 1, at: Date.now()});
        try {
            if (p.isSubtitlesOn?.()) {
                // Already on but no request seen (it went out before we were
                // listening): cycle them to make the player ask again.
                p.toggleSubtitles();
                setTimeout(() => p.toggleSubtitlesOn(), 300);
            } else {
                p.toggleSubtitlesOn();
                const check = setInterval(() => {
                    if (!tokens.has(v)) return;
                    clearInterval(check);
                    if (p.isSubtitlesOn?.()) p.toggleSubtitles();
                }, 250);
                setTimeout(() => clearInterval(check), 8000);
            }
        } catch { /* ignore */
        }
    }

    let lastPublished = '';

    /**
     * Copied onto a DOM attribute rather than posted, so the content script can
     * read it synchronously whenever it likes instead of racing a message.
     *
     * Read from the player itself: `ytInitialPlayerResponse` is only the page
     * YouTube first loaded, and is never updated as you click between videos.
     */
    function exposeYouTube() {
        try {
            const p = ytPlayer();
            const pr = p?.getPlayerResponse?.() || (window as any).ytInitialPlayerResponse;
            const v: string = pr?.videoDetails?.videoId || '';
            if (!v || v !== new URLSearchParams(location.search).get('v')) return;

            const tracks = pr?.captions?.playerCaptionsTracklistRenderer?.captionTracks;
            // During an ad the player still reports the main video's id, but
            // its audio tracks and captions are the ad's; leave it alone.
            const inAd = !!p?.classList?.contains('ad-showing');
            if (active && p && !inAd) {
                keepOriginalAudio(p, v);
                if (Array.isArray(tracks) && tracks.length) provokeCaptionRequest(p, v);
            }

            const payload = JSON.stringify({
                v,
                token: tokens.get(v) || null,
                audio: p && !inAd ? langOf(p.getAudioTrack?.()) : '',
                tracks: (Array.isArray(tracks) ? tracks : []).map((t: any) => ({
                    baseUrl: t.baseUrl,
                    languageCode: t.languageCode,
                    name: t.name?.simpleText || t.name?.runs?.[0]?.text || t.languageCode,
                    kind: t.kind,
                })),
            });
            if (payload === lastPublished) return;
            lastPublished = payload;
            // Stamped with the video id: the content script refuses a payload
            // that does not match the URL it is looking at.
            document.documentElement.setAttribute('data-majortom-yt', payload);
            post({kind: 'yt-update', v});
            const title = pr?.videoDetails?.title;
            if (title) post({kind: 'media-meta', title});
        } catch { /* ignore */
        }
    }

    if (isYouTube) {
        // Cheap, and the only thing that reliably notices everything: SPA
        // navigations, ads ending, the audio track list appearing.
        setInterval(exposeYouTube, 1000);
        window.addEventListener('yt-navigate-start', () => {
            document.documentElement.removeAttribute('data-majortom-yt');
            lastPublished = '';
        });
        window.addEventListener('yt-navigate-finish', exposeYouTube);
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

        if (isYtTimedtext(url)) {
            noteYtToken(url);
        } else if (url && !NOISE.test(url)) {
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

    /**
     * Patches `open` on the prototype rather than replacing the constructor.
     * Ad blockers (uBlock, Brave Shields) subclass XMLHttpRequest on YouTube;
     * a replaced constructor that returns a plain instance would silently drop
     * their subclass methods, whichever of us loaded first. A prototype patch
     * stacks cleanly with theirs in either order.
     */
    const xhrUrls = new WeakMap<XMLHttpRequest, string>();
    const origOpen = XMLHttpRequest.prototype.open;

    XMLHttpRequest.prototype.open = function (this: XMLHttpRequest, _method: string, u: string | URL) {
        const url = String(u);
        if (isYtTimedtext(url)) noteYtToken(url);
        else if (!xhrUrls.has(this)) this.addEventListener('load', onXhrLoad);
        xhrUrls.set(this, url);
        return origOpen.apply(this, arguments as any);
    } as typeof XMLHttpRequest.prototype.open;

    function onXhrLoad(this: XMLHttpRequest) {
        try {
            const url = xhrUrls.get(this) || '';
            // responseText throws for non-text responseTypes — check before reading.
            if (this.responseType && this.responseType !== 'text') return;
            // The YouTube adapter fetches its own tracks with the token.
            if (isYtTimedtext(url)) return;
            const ct = this.getResponseHeader('content-type');
            if (interesting(url, ct)) {
                emitSubFile(url, this.responseText || '');
            } else if (hungry && ct && /text|json|xml/i.test(ct)) {
                const body = this.responseText || '';
                if (body.length <= 4 * 1024 * 1024 && looksLikeSubtitles(body)) emitSubFile(url, body);
            }
        } catch { /* ignore */
        }
    }
})();
