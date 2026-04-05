(() => {
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
})();
