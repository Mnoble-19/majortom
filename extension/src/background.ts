chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.local.set({
    majortom: {
      enabled: true,
      primaryLang: 'de',
      secondaryLang: 'en',
      savedWords: [],
    },
  });
});
