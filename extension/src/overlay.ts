import { Cue, SavedWord } from './types';
import { saveWord, unsaveWord, getSavedWords } from './storage';

export class SubtitleOverlay {
  private container: HTMLElement;
  private primaryEl: HTMLElement;
  private secondaryEl: HTMLElement;
  private controlBar: HTMLElement;
  private video: HTMLVideoElement;
  private primaryCues: Cue[] = [];
  private secondaryCues: Cue[] = [];
  private currentPrimaryIdx = -1;
  private currentSecondaryIdx = -1;
  private savedWords: Set<string> = new Set();
  private programTitle = '';
  private source = '';

  constructor(video: HTMLVideoElement) {
    this.video = video;
    this.source = window.location.hostname;

    this.container = document.createElement('div');
    this.container.id = 'majortom-overlay';

    this.controlBar = document.createElement('div');
    this.controlBar.id = 'majortom-controls';
    this.controlBar.innerHTML = `
      <span class="majortom-logo">MajorTom</span>
      <select id="majortom-primary-lang"></select>
      <select id="majortom-secondary-lang"></select>
      <button id="majortom-toggle">Hide</button>
    `;

    this.primaryEl = document.createElement('div');
    this.primaryEl.id = 'majortom-primary';
    this.primaryEl.className = 'majortom-subtitle-line';

    this.secondaryEl = document.createElement('div');
    this.secondaryEl.id = 'majortom-secondary';
    this.secondaryEl.className = 'majortom-subtitle-line';

    this.container.appendChild(this.primaryEl);
    this.container.appendChild(this.secondaryEl);

    this.loadSavedWords();
    this.setupSync();
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
    parent.appendChild(this.controlBar);
    parent.appendChild(this.container);
  }

  unmount() {
    this.container.remove();
    this.controlBar.remove();
  }

  setCues(primary: Cue[], secondary: Cue[]) {
    this.primaryCues = primary;
    this.secondaryCues = secondary;
    this.currentPrimaryIdx = -1;
    this.currentSecondaryIdx = -1;
  }

  populateLanguageSelectors(
    tracks: { label: string; languageCode: string }[],
    onSelect: (primaryLang: string, secondaryLang: string) => void
  ) {
    const primary = this.controlBar.querySelector('#majortom-primary-lang') as HTMLSelectElement;
    const secondary = this.controlBar.querySelector('#majortom-secondary-lang') as HTMLSelectElement;

    const addMachineTranslateOptions = (select: HTMLSelectElement) => {
      const optgroup = document.createElement('optgroup');
      optgroup.label = 'Machine Translate';
      ['en', 'de', 'fr', 'es', 'pt', 'it', 'ja', 'ko', 'zh', 'ar', 'tr', 'ru'].forEach(code => {
        if (!tracks.find(t => t.languageCode === code)) {
          const opt = document.createElement('option');
          opt.value = `mt:${code}`;
          opt.textContent = `[MT] ${code.toUpperCase()}`;
          optgroup.appendChild(opt);
        }
      });
      select.appendChild(optgroup);
    };

    [primary, secondary].forEach(select => {
      select.innerHTML = '';
      tracks.forEach(t => {
        const opt = document.createElement('option');
        opt.value = t.languageCode;
        opt.textContent = t.label;
        select.appendChild(opt);
      });
      addMachineTranslateOptions(select);
    });

    const dePrim = tracks.find(t => t.languageCode === 'de');
    if (dePrim) primary.value = 'de';

    const enSec = tracks.find(t => t.languageCode === 'en');
    if (enSec) secondary.value = 'en';
    else secondary.value = `mt:en`;

    const toggle = this.controlBar.querySelector('#majortom-toggle') as HTMLButtonElement;
    toggle.addEventListener('click', () => {
      const hidden = this.container.style.display === 'none';
      this.container.style.display = hidden ? '' : 'none';
      toggle.textContent = hidden ? 'Hide' : 'Show';
    });

    const emitChange = () => onSelect(primary.value, secondary.value);
    primary.addEventListener('change', emitChange);
    secondary.addEventListener('change', emitChange);
    emitChange();
  }

  private setupSync() {
    this.video.addEventListener('timeupdate', () => this.render());
  }

  private render() {
    const t = this.video.currentTime;
    this.renderLine(this.primaryEl, this.primaryCues, t, true);
    this.renderLine(this.secondaryEl, this.secondaryCues, t, false);
  }

  private renderLine(el: HTMLElement, cues: Cue[], time: number, isPrimary: boolean) {
    const cue = cues.find(c => time >= c.start && time <= c.end);
    if (!cue) {
      el.innerHTML = '';
      return;
    }

    const idx = cues.indexOf(cue);
    const idxProp = isPrimary ? 'currentPrimaryIdx' : 'currentSecondaryIdx';
    if (this[idxProp] === idx) return;
    this[idxProp] = idx;

    if (isPrimary) {
      el.innerHTML = cue.text
        .split(/(\s+)/)
        .map(word => {
          if (!word.trim()) return word;
          const clean = word.replace(/[.,!?;:'"()]/g, '').toLowerCase();
          const isSaved = this.savedWords.has(clean);
          const cls = isSaved ? 'majortom-word majortom-saved' : 'majortom-word';
          return `<span class="${cls}" data-word="${this.escapeAttr(clean)}">${word}</span>`;
        })
        .join('');

      el.querySelectorAll('.majortom-word').forEach(span => {
        span.addEventListener('click', (e) => this.handleWordClick(e, cue.text));
      });
    } else {
      el.textContent = cue.text;
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
        this.jumpCaption(-1);
      } else if (e.key === 's' || e.key === 'S') {
        e.preventDefault();
        this.jumpCaption(1);
      }
    });
  }

  private jumpCaption(direction: number) {
    if (!this.primaryCues.length) return;

    const t = this.video.currentTime;
    let idx = this.primaryCues.findIndex(c => t >= c.start && t <= c.end);
    if (idx === -1) {
      idx = this.primaryCues.findIndex(c => c.start > t);
      if (idx === -1) idx = this.primaryCues.length - 1;
      if (direction === -1) idx = Math.max(0, idx - 1);
    } else {
      idx = Math.max(0, Math.min(this.primaryCues.length - 1, idx + direction));
    }

    this.video.currentTime = this.primaryCues[idx].start;
    this.video.pause();
    this.render();
  }

  private escapeAttr(s: string): string {
    return s.replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }
}
