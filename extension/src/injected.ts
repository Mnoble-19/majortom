(() => {
  // ── YouTube: extract track list from player response ──────────────────────
  function extractTracks() {
    const playerResponse =
      (window as any).ytInitialPlayerResponse ||
      (window as any).ytplayer?.config?.args?.raw_player_response;

    if (!playerResponse?.captions?.playerCaptionsTracklistRenderer) return;

    const renderer = playerResponse.captions.playerCaptionsTracklistRenderer;
    const tracks = (renderer.captionTracks || []).map((t: any) => ({
      label: t.name?.simpleText || t.languageCode,
      languageCode: t.languageCode,
      url: t.baseUrl,
      isTranslatable: t.isTranslatable || false,
    }));

    const title = playerResponse.videoDetails?.title || '';
    const channel = playerResponse.videoDetails?.author || '';

    window.postMessage({ type: 'MAJORTOM_TRACKS', tracks, title, channel }, '*');
  }

  extractTracks();

  const origPushState = history.pushState;
  history.pushState = function (...args) {
    origPushState.apply(this, args);
    setTimeout(extractTracks, 1500);
  };

  window.addEventListener('yt-navigate-finish', () => {
    setTimeout(extractTracks, 1500);
  });

  // ── Intercept XHR: capture YouTube's own subtitle fetches ─────────────────
  // YouTube fetches timedtext itself; we piggyback on that response
  // so we never have auth/expiry issues re-fetching the URL ourselves.
  const OrigXHR = window.XMLHttpRequest;
  (window as any).XMLHttpRequest = function () {
    const xhr = new OrigXHR();
    let _url = '';

    const _open = xhr.open.bind(xhr);
    (xhr as any).open = function (method: string, url: string, ...rest: any[]) {
      _url = url;
      return _open(method, url, ...rest);
    };

    xhr.addEventListener('load', function () {
      if (_url && !_url.includes('doubleclick') && !_url.includes('analytics') && !_url.includes('googlevideo')) {
        window.postMessage({ type: 'MAJORTOM_URL_SEEN', url: _url, via: 'xhr' }, '*');
      }
      if (isTimedTextUrl(_url) && xhr.responseText) {
        window.postMessage({
          type: 'MAJORTOM_SUBTITLE_INTERCEPTED',
          url: _url,
          content: xhr.responseText,
        }, '*');
      }
    });

    return xhr;
  };
  // Copy static props (DONE, LOADING, etc.)
  Object.assign((window as any).XMLHttpRequest, OrigXHR);

  // Also intercept fetch (YouTube sometimes uses it)
  const _origFetch = window.fetch.bind(window);
  window.fetch = function (input: RequestInfo | URL, init?: RequestInit) {
    const url = typeof input === 'string' ? input
      : input instanceof URL ? input.href
      : (input as Request).url;
    const p = _origFetch(input, init);
    if (url && !url.includes('doubleclick') && !url.includes('analytics') && !url.includes('googlevideo')) {
      window.postMessage({ type: 'MAJORTOM_URL_SEEN', url, via: 'fetch' }, '*');
    }
    if (isTimedTextUrl(url)) {
      p.then(r => r.clone().text()).then(text => {
        if (text) {
          window.postMessage({
            type: 'MAJORTOM_SUBTITLE_INTERCEPTED',
            url,
            content: text,
          }, '*');
        }
      }).catch(() => {});
    }
    return p;
  };

  function isTimedTextUrl(url: string): boolean {
    return (
      // YouTube
      url.includes('timedtext') ||
      url.includes('youtube.com/api/timedtext') ||
      // ZDF — EBU-TT XML subtitles
      url.includes('utstreaming.zdf.de') ||
      (url.includes('zdf.de') && (url.includes('.xml') || url.includes('subtitle') || url.includes('caption'))) ||
      // ARD Mediathek — VTT subtitles
      (url.includes('ard') && url.includes('.vtt')) ||
      url.includes('srt.ardmediathek.de') ||
      url.includes('avid.ardmediathek.de') ||
      url.includes('.vtt') && (url.includes('ardmediathek') || url.includes('daserste') || url.includes('mdr') || url.includes('ndr') || url.includes('wdr'))
    );
  }
})();
