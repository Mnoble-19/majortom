import {Settings} from '../shared/types';

export interface OverlayHooks {
    isSaved(word: string): boolean;

    lookup(word: string): Promise<string>;

    saveWord(word: string, translation: string): Promise<void>;

    removeWord(word: string): Promise<void>;

    patchSettings(patch: Partial<Settings>): void;

    seekToCue(delta: number): void;

    replayCue(): void;
}

const STYLE = `
:host { all: initial; }
* { box-sizing: border-box; font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }

.root {
  position: absolute; left: 50%; transform: translateX(-50%);
  width: min(92%, 1100px); z-index: 2147483000;
  display: flex; flex-direction: column; align-items: center; gap: 6px;
  pointer-events: none; user-select: none;
  transition: bottom .18s ease;
}

/* Toolbar sits above the lines and only appears when the player is hovered. */
.bar {
  display: flex; gap: 4px; align-items: center; padding: 5px;
  border-radius: 12px; background: rgba(16,16,22,.82);
  backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px);
  box-shadow: 0 2px 14px rgba(0,0,0,.45);
  opacity: 0; transition: opacity .16s ease; pointer-events: auto;
}
.root:hover .bar, .bar.pinned { opacity: 1; }
.bar button {
  all: unset; cursor: pointer; display: grid; place-items: center;
  width: 38px; height: 34px; border-radius: 8px; color: #cfd2dc;
  font-size: 17px; line-height: 1;
}
.bar button:hover { background: rgba(255,255,255,.14); color: #fff; }
.bar button[aria-pressed="true"] { background: rgba(126,200,227,.26); color: #9fe0f5; }
.bar .sep { width: 1px; height: 20px; background: rgba(255,255,255,.16); margin: 0 4px; }

.line {
  pointer-events: auto; text-align: center; max-width: 100%;
  padding: .18em .6em; border-radius: 8px;
  background: rgba(8,8,10,.76);
  backdrop-filter: blur(3px); -webkit-backdrop-filter: blur(3px);
  line-height: 1.34; text-wrap: balance;
}
.line:empty { display: none; }
/* Re-triggered on every cue change so lines arrive rather than snap. */
.line.swap { animation: mt-in .15s ease-out; }
@keyframes mt-in { from { opacity: .2; transform: translateY(3px); } to { opacity: 1; transform: none; } }
@media (prefers-reduced-motion: reduce) { .line.swap { animation: none; } }

.primary { font-size: var(--mt-size); font-weight: 550; color: #fff; letter-spacing: .002em; }
.secondary {
  font-size: calc(var(--mt-size) * .68); color: #b9bdcb; font-weight: 450;
  background: rgba(8,8,10,.6);
}
/* "Try first" mode: the translation is there, but you have to reach for it. */
.secondary.blurred { filter: blur(7px); transition: filter .12s ease; cursor: pointer; }
.secondary.blurred:hover { filter: none; }

.w { cursor: pointer; border-radius: 4px; padding: 0 .04em; transition: background .1s, color .1s; }
.w:hover { background: rgba(126,200,227,.28); color: #cfefff; }
.w.saved { color: #ffd479; box-shadow: inset 0 -2px 0 rgba(255,212,121,.55); }
.w.active { background: rgba(126,200,227,.4); color: #fff; }

.status {
  pointer-events: none; font-size: 11px; color: #9aa0b0; letter-spacing: .03em;
  background: rgba(16,16,22,.8); padding: 3px 9px; border-radius: 999px;
}
.status:empty { display: none; }

/* Word lookup card */
.card {
  position: absolute; bottom: calc(100% + 10px); left: 50%; transform: translateX(-50%);
  min-width: 190px; max-width: 320px; pointer-events: auto;
  background: rgba(20,20,28,.97); color: #eceef4;
  border: 1px solid rgba(255,255,255,.1); border-radius: 12px;
  box-shadow: 0 10px 34px rgba(0,0,0,.55); padding: 11px 13px;
  font-size: 13px; text-align: left; display: none;
}
.card.open { display: block; }
.card .hw { font-size: 16px; font-weight: 650; color: #ffd479; margin-bottom: 3px; word-break: break-word; }
.card .tr { color: #dfe3ee; min-height: 1.2em; margin-bottom: 9px; line-height: 1.4; }
.card .tr.dim { color: #7f8598; font-style: italic; }
.card .row { display: flex; gap: 7px; }
.card button {
  all: unset; cursor: pointer; padding: 5px 11px; border-radius: 7px;
  font-size: 12px; font-weight: 550; text-align: center;
}
.card .save { background: #2f6f8f; color: #eaf7ff; }
.card .save:hover { background: #3b87ac; }
.card .save.on { background: #6b5a20; color: #ffd479; }
.card .close { color: #9aa0b0; }
.card .close:hover { background: rgba(255,255,255,.1); color: #fff; }
`;

/** Word-ish runs, keeping apostrophes/hyphens inside words. Unicode-aware. */
const WORD_RE = /[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*/gu;

export class Overlay {
    private host: HTMLElement;
    private shadow: ShadowRoot;
    private root: HTMLElement;
    private primaryEl: HTMLElement;
    private secondaryEl: HTMLElement;
    private statusEl: HTMLElement;
    private card: HTMLElement;
    private cardWord!: HTMLElement;
    private cardTr!: HTMLElement;
    private cardSave!: HTMLButtonElement;
    private bar: HTMLElement;
    private barToggles!: {
        blur: HTMLButtonElement;
        pause: HTMLButtonElement;
        loop: HTMLButtonElement;
    };
    private statusTimer = 0;

    private lastPrimary = '';
    private lastSecondary = '';
    private activeWord: HTMLElement | null = null;
    private resizeObs: ResizeObserver | null = null;
    private parent: HTMLElement | null = null;
    /** Player controls appear on hover, so lift out of their way while they do. */
    private lifted = false;

    constructor(
        private video: HTMLVideoElement,
        private settings: Settings,
        private hooks: OverlayHooks,
    ) {
        this.host = document.createElement('div');
        this.host.id = 'majortom-root';
        // Isolate from page CSS entirely — this is what keeps it looking the same
        // on every site instead of inheriting whatever the player does.
        this.host.style.cssText = 'all:initial;position:absolute;inset:0;pointer-events:none;z-index:2147483000';
        this.shadow = this.host.attachShadow({mode: 'open'});

        const style = document.createElement('style');
        style.textContent = STYLE;
        this.shadow.appendChild(style);

        this.root = el('div', 'root');
        this.bar = this.buildBar();
        this.statusEl = el('div', 'status');
        this.secondaryEl = el('div', 'line secondary');
        this.primaryEl = el('div', 'line primary');
        this.card = this.buildCard();

        this.root.append(this.card, this.bar, this.statusEl, this.primaryEl, this.secondaryEl);
        this.shadow.appendChild(this.root);

        this.applySettings(settings);
    }

    mount(): void {
        this.attachToBestParent();
        document.addEventListener('fullscreenchange', this.onFullscreen);
        document.addEventListener('webkitfullscreenchange', this.onFullscreen);
        document.addEventListener('click', this.onDocClick, true);
    }

    unmount(): void {
        document.removeEventListener('fullscreenchange', this.onFullscreen);
        document.removeEventListener('webkitfullscreenchange', this.onFullscreen);
        document.removeEventListener('click', this.onDocClick, true);
        this.parent?.removeEventListener('mouseenter', this.onEnter);
        this.parent?.removeEventListener('mouseleave', this.onLeave);
        this.resizeObs?.disconnect();
        this.resizeObs = null;
        this.host.remove();
    }

    setLines(primary: string, secondary: string): void {
        if (primary !== this.lastPrimary) {
            this.lastPrimary = primary;
            this.closeCard();
            this.renderWords(primary);
            if (primary) replay(this.primaryEl);
        }
        if (secondary !== this.lastSecondary) {
            this.lastSecondary = secondary;
            this.secondaryEl.textContent = secondary;
            if (secondary) replay(this.secondaryEl);
        }
    }

    /** `autoHideMs` clears the message again, for one-off notices. */
    setStatus(text: string, autoHideMs = 0): void {
        this.statusEl.textContent = text;
        clearTimeout(this.statusTimer);
        if (text && autoHideMs > 0) {
            this.statusTimer = self.setTimeout(() => {
                this.statusEl.textContent = '';
            }, autoHideMs);
        }
    }

    /* ── Mount / layout ─────────────────────────────────────────────────────── */

    /** Repaint saved-state highlighting without rebuilding the line. */
    refreshSaved(): void {
        this.primaryEl.querySelectorAll('.w').forEach(node => {
            const span = node as HTMLElement;
            span.classList.toggle('saved', this.hooks.isSaved(norm(span.textContent || '')));
        });
    }

    applySettings(s: Settings): void {
        this.settings = s;
        this.secondaryEl.classList.toggle('blurred', s.blurSecondary);
        this.secondaryEl.style.display = s.showSecondary ? '' : 'none';
        this.barToggles?.blur.setAttribute('aria-pressed', String(s.blurSecondary));
        this.barToggles?.pause.setAttribute('aria-pressed', String(s.autoPause));
        this.barToggles?.loop.setAttribute('aria-pressed', String(s.loopCue));
        this.scale();
    }

    private onEnter = () => {
        this.lifted = true;
        this.scale();
    };

    private onLeave = () => {
        this.lifted = false;
        this.scale();
    };

    /* ── Content ────────────────────────────────────────────────────────────── */

    private onFullscreen = () => this.attachToBestParent();

    private onDocClick = (e: Event) => {
        if (!this.card.classList.contains('open')) return;
        if (!e.composedPath().includes(this.card)) this.closeCard();
    };

    /**
     * Anchor to whatever box the video actually occupies — the fullscreen element
     * when there is one, otherwise the nearest positioned ancestor.
     */
    private attachToBestParent(): void {
        const fs = (document.fullscreenElement || (document as any).webkitFullscreenElement) as HTMLElement | null;
        let parent: HTMLElement | null = null;

        if (fs) {
            parent = fs;
        } else {
            let n: HTMLElement | null = this.video.parentElement;
            while (n && n !== document.body) {
                const cs = getComputedStyle(n);
                if (cs.position !== 'static' && n.clientHeight > 80) break;
                n = n.parentElement;
            }
            parent = n || this.video.parentElement;
        }
        if (!parent) return;

        if (getComputedStyle(parent).position === 'static') parent.style.position = 'relative';

        this.parent?.removeEventListener('mouseenter', this.onEnter);
        this.parent?.removeEventListener('mouseleave', this.onLeave);
        parent.appendChild(this.host);
        this.parent = parent;
        parent.addEventListener('mouseenter', this.onEnter);
        parent.addEventListener('mouseleave', this.onLeave);

        this.resizeObs?.disconnect();
        this.resizeObs = new ResizeObserver(() => this.scale());
        this.resizeObs.observe(parent);
        this.scale();
    }

    /** Type size tracks the player's width, so it reads the same at any size. */
    private scale(): void {
        const w = this.parent?.clientWidth || 800;
        const px = Math.max(15, Math.min(46, w * 0.0265)) * (this.settings.fontScale || 1);
        this.root.style.setProperty('--mt-size', `${px.toFixed(1)}px`);
        this.root.style.bottom = `${this.settings.offsetPct + (this.lifted ? 9 : 0)}%`;
    }

    /* ── Word card ──────────────────────────────────────────────────────────── */

    /** Build the primary line as clickable word spans, without any innerHTML. */
    private renderWords(text: string): void {
        this.primaryEl.textContent = '';
        if (!text) return;

        const frag = document.createDocumentFragment();
        let last = 0;
        for (const m of text.matchAll(WORD_RE)) {
            const i = m.index ?? 0;
            if (i > last) frag.appendChild(document.createTextNode(text.slice(last, i)));

            const span = el('span', 'w');
            span.textContent = m[0];
            if (this.hooks.isSaved(norm(m[0]))) span.classList.add('saved');
            span.addEventListener('click', e => {
                e.stopPropagation();
                this.openCard(span, m[0]);
            });
            frag.appendChild(span);
            last = i + m[0].length;
        }
        if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
        this.primaryEl.appendChild(frag);
    }

    private buildCard(): HTMLElement {
        const card = el('div', 'card');
        this.cardWord = el('div', 'hw');
        this.cardTr = el('div', 'tr');

        this.cardSave = el('button', 'save') as HTMLButtonElement;
        const close = el('button', 'close') as HTMLButtonElement;
        close.textContent = 'Close';
        close.addEventListener('click', () => this.closeCard());

        const row = el('div', 'row');
        row.append(this.cardSave, close);
        card.append(this.cardWord, this.cardTr, row);
        return card;
    }

    private async openCard(span: HTMLElement, raw: string): Promise<void> {
        const word = norm(raw);
        this.activeWord?.classList.remove('active');
        this.activeWord = span;
        span.classList.add('active');

        this.cardWord.textContent = raw;
        this.card.classList.add('open');

        const saved = this.hooks.isSaved(word);
        this.setSaveButton(saved);
        this.cardSave.onclick = async () => {
            if (this.hooks.isSaved(word)) {
                await this.hooks.removeWord(word);
                this.setSaveButton(false);
            } else {
                await this.hooks.saveWord(word, this.cardTr.textContent || '');
                this.setSaveButton(true);
            }
            this.refreshSaved();
        };

        this.cardTr.textContent = 'Looking up…';
        this.cardTr.classList.add('dim');
        const tr = await this.hooks.lookup(word);
        // The user may have clicked elsewhere while the lookup was in flight.
        if (this.activeWord !== span) return;
        this.cardTr.textContent = tr || 'No translation (check your DeepL key in settings)';
        this.cardTr.classList.toggle('dim', !tr);
    }

    private setSaveButton(saved: boolean): void {
        this.cardSave.textContent = saved ? '★ Saved' : '+ Save word';
        this.cardSave.classList.toggle('on', saved);
    }

    /* ── Toolbar ────────────────────────────────────────────────────────────── */

    private closeCard(): void {
        this.card.classList.remove('open');
        this.activeWord?.classList.remove('active');
        this.activeWord = null;
    }

    /* ── Settings ───────────────────────────────────────────────────────────── */

    private buildBar(): HTMLElement {
        const bar = el('div', 'bar');

        const mk = (label: string, title: string, fn: () => void) => {
            const b = el('button') as HTMLButtonElement;
            b.textContent = label;
            b.title = title;
            b.addEventListener('click', e => {
                e.stopPropagation();
                fn();
            });
            bar.appendChild(b);
            return b;
        };

        mk('‹', 'Previous subtitle  [ ', () => this.hooks.seekToCue(-1));
        mk('⟲', 'Replay this subtitle  \\', () => this.hooks.replayCue());
        mk('›', 'Next subtitle  ]', () => this.hooks.seekToCue(1));
        bar.appendChild(el('div', 'sep'));

        const blur = mk('👁', 'Hide translation until hovered', () => {
            const v = !this.settings.blurSecondary;
            this.hooks.patchSettings({blurSecondary: v});
        });
        const pause = mk('⏸', 'Auto-pause at the end of each subtitle  P', () => {
            this.hooks.patchSettings({autoPause: !this.settings.autoPause});
        });
        const loop = mk('↻', 'Loop this subtitle  L', () => {
            this.hooks.patchSettings({loopCue: !this.settings.loopCue});
        });

        this.barToggles = {blur, pause, loop};
        return bar;
    }
}

/** Restart the entry animation on an element whose content just changed. */
function replay(node: HTMLElement): void {
    node.classList.remove('swap');
    void node.offsetWidth; // force reflow so the animation re-runs
    node.classList.add('swap');
}

function el(tag: string, cls = ''): HTMLElement {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    return n;
}

/** Canonical form used as the vocabulary key. */
export function norm(w: string): string {
    return w.replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, '').toLowerCase();
}
