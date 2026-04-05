import { SavedWord } from './types';
import { saveWord, unsaveWord, getSavedWords } from './storage';

export class SubtitleOverlay {
  private container: HTMLElement;
  private primaryEl: HTMLElement;
  private secondaryEl: HTMLElement;
  private video: HTMLVideoElement;
  private savedWords: Set<string> = new Set();
  private programTitle = '';
  private source = '';
  private lastPrimary = '';
  private lastSecondary = '';

  constructor(video: HTMLVideoElement) {
    this.video = video;
    this.source = window.location.hostname;

    this.container = document.createElement('div');
    this.container.id = 'majortom-overlay';

    this.primaryEl = document.createElement('div');
    this.primaryEl.id = 'majortom-primary';
    this.primaryEl.className = 'majortom-subtitle-line';

    this.secondaryEl = document.createElement('div');
    this.secondaryEl.id = 'majortom-secondary';
    this.secondaryEl.className = 'majortom-subtitle-line';

    this.container.appendChild(this.primaryEl);
    this.container.appendChild(this.secondaryEl);

    this.loadSavedWords();
    this.setupKeyboard();
  }

  private async loadSavedWords() {
    const words = await getSavedWords();
    this.savedWords = new Set(words.map(w => w.word.toLowerCase()));
  }

  setTitle(title: string) {
    this.programTitle = title;
  }

  mount(parent: HTMLElement) {
    parent.style.position = 'relative';
    parent.appendChild(this.container);
  }

  unmount() {
    this.container.remove();
  }

  setLiveText(primary: string, secondary: string) {
    if (primary !== this.lastPrimary) {
      this.lastPrimary = primary;
      if (primary) {
        this.primaryEl.innerHTML = primary
          .split(/(\s+)/)
          .map(word => {
            if (!word.trim()) return word;
            const clean = word.replace(/[.,!?;:'"()]/g, '').toLowerCase();
            const isSaved = this.savedWords.has(clean);
            const cls = isSaved ? 'majortom-word majortom-saved' : 'majortom-word';
            return `<span class="${cls}" data-word="${this.escapeAttr(clean)}">${word}</span>`;
          })
          .join('');
        this.primaryEl.querySelectorAll('.majortom-word').forEach(span => {
          span.addEventListener('click', (e) => this.handleWordClick(e, primary));
        });
      } else {
        this.primaryEl.innerHTML = '';
      }
    }
    if (secondary !== this.lastSecondary) {
      this.lastSecondary = secondary;
      this.secondaryEl.textContent = secondary;
    }
  }

  private async handleWordClick(e: Event, context: string) {
    const span = e.target as HTMLElement;
    const word = span.dataset.word || '';

    if (this.savedWords.has(word)) {
      this.savedWords.delete(word);
      await unsaveWord(word);
      span.classList.remove('majortom-saved');
    } else {
      this.savedWords.add(word);
      await saveWord({
        word,
        translation: '',
        context,
        source: this.source,
        program: this.programTitle,
        date: new Date().toISOString().split('T')[0],
        starred: false,
      });
      span.classList.add('majortom-saved');
    }
  }

  private setupKeyboard() {
    document.addEventListener('keydown', (e) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;

      if (e.key === 'a' || e.key === 'A') {
        e.preventDefault();
        e.stopPropagation();
        this.video.currentTime = Math.max(0, this.video.currentTime - 5);
      } else if (e.key === 's' || e.key === 'S') {
        e.preventDefault();
        e.stopPropagation();
        this.video.currentTime += 5;
      }
    }, true);
  }

  private escapeAttr(s: string): string {
    return s.replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }
}
