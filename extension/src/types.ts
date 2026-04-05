export interface Cue {
  start: number;
  end: number;
  text: string;
}

export interface SubtitleTrack {
  label: string;
  languageCode: string;
  url: string;
  isTranslatable?: boolean;
}

export interface SavedWord {
  word: string;
  translation: string;
  context: string;
  source: string;
  program: string;
  date: string;
  starred: boolean;
}

export interface MajorTomState {
  enabled: boolean;
  primaryLang: string;
  secondaryLang: string;
  savedWords: SavedWord[];
}

export type MessageType =
  | { type: 'TRACKS_DISCOVERED'; tracks: SubtitleTrack[] }
  | { type: 'VIDEO_INFO'; title: string; channel: string };
