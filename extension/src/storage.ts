import { SavedWord, MajorTomState } from './types';

const DEFAULT_STATE: MajorTomState = {
  enabled: true,
  primaryLang: 'de',
  secondaryLang: 'en',
  savedWords: [],
};

export async function getState(): Promise<MajorTomState> {
  const result = await chrome.storage.local.get('majortom');
  return { ...DEFAULT_STATE, ...result.majortom };
}

export async function setState(partial: Partial<MajorTomState>): Promise<void> {
  const current = await getState();
  await chrome.storage.local.set({ majortom: { ...current, ...partial } });
}

export async function saveWord(word: SavedWord): Promise<void> {
  const state = await getState();
  const exists = state.savedWords.some(
    w => w.word === word.word && w.program === word.program
  );
  if (!exists) {
    state.savedWords.push(word);
    await setState({ savedWords: state.savedWords });
  }
}

export async function unsaveWord(word: string): Promise<void> {
  const state = await getState();
  state.savedWords = state.savedWords.filter(w => w.word !== word);
  await setState({ savedWords: state.savedWords });
}

export async function toggleStar(word: string): Promise<void> {
  const state = await getState();
  const found = state.savedWords.find(w => w.word === word);
  if (found) {
    found.starred = !found.starred;
    await setState({ savedWords: state.savedWords });
  }
}

export async function getSavedWords(): Promise<SavedWord[]> {
  const state = await getState();
  return state.savedWords;
}
