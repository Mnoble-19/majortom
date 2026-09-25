import {Gloss, Settings} from '../shared/types';

export interface OverlayHooks {
    isSaved(word: string): boolean;

    lookup(word: string): Promise<Gloss | { error: string }>;

    saveWord(word: string, translation: string): Promise<void>;

    removeWord(word: string): Promise<void>;

    patchSettings(patch: Partial<Settings>): void;

    seekToCue(delta: number): void;

    replayCue(): void;
}

const STYLE = `
:host { all: initial; }
* { box-sizing: border-box; font-family: ui-rounded, "SF Pro Rounded", system-ui, -apple-system, "Segoe UI", sans-serif; }

.root {
  --accent: #6c4df5; --accent-text: #5a3be0;
  --card: rgba(255,255,255,.97); --card-fg: #1c1c1e; --card-dim: #5e5e63; --raised: #f1eff6;
  --highlight: #ffe08a; --on-highlight: #2e2100;
  position: absolute; left: 50%; transform: translateX(-50%);
  width: min(92%, 1100px); z-index: 2147483000;
  display: flex; flex-direction: column; align-items: center; gap: 8px;
  pointer-events: none; user-select: none;
  transition: bottom .18s ease;
}
@media (prefers-color-scheme: dark) {
  .root {
    --accent: #7f66ff; --accent-text: #b3a5ff;
    --card: rgba(29,29,34,.97); --card-fg: #e9e9ee; --card-dim: #a3a3ad; --raised: #2c2c34;
  }
}

/* Toolbar sits above the lines and only appears when the player is hovered. */
.bar {
  display: flex; gap: 2px; align-items: center; padding: 5px;
  border-radius: 22px; background: rgba(28,28,32,.82);
  backdrop-filter: blur(14px); -webkit-backdrop-filter: blur(14px);
  box-shadow: 0 6px 20px rgba(0,0,0,.35);
  opacity: 0; transition: opacity .16s ease; pointer-events: auto;
}
.root:hover .bar, .bar.pinned { opacity: 1; }
.bar button {
  all: unset; cursor: pointer; display: grid; place-items: center;
  width: 40px; height: 36px; border-radius: 18px; color: #e6e7eb;
}
.bar button svg { width: 18px; height: 18px; }
.bar button:hover { background: rgba(255,255,255,.14); color: #fff; }
.bar button[aria-pressed="true"] { background: var(--accent); color: #fff; }
.bar button:focus-visible { outline: 2px solid #fff; outline-offset: 1px; }
.bar .sep { width: 1px; height: 20px; background: rgba(255,255,255,.18); margin: 0 4px; }

.line {
  pointer-events: auto; text-align: center; max-width: 100%;
  padding: 0 .4em; line-height: 1.32; text-wrap: balance;
  /* No box behind the text: a tight dark halo keeps it readable on any frame. */
  text-shadow: 0 0 2px rgba(0,0,0,.95), 0 1px 3px rgba(0,0,0,.9), 0 0 14px rgba(0,0,0,.55);
}
.line:empty { display: none; }
/* Re-triggered on every cue change so lines arrive rather than snap. */
.line.swap { animation: mt-in .15s ease-out; }
@keyframes mt-in { from { opacity: .2; transform: translateY(3px); } to { opacity: 1; transform: none; } }
@media (prefers-reduced-motion: reduce) { .line.swap { animation: none; } }

.primary { font-size: var(--mt-size); font-weight: 650; color: #fff; letter-spacing: .002em; }
.secondary {
  font-size: calc(var(--mt-size) * .72); color: #e4e5ea; font-weight: 550;
}
/* "Try first" mode: the translation is there, but you have to reach for it. */
.secondary.blurred { filter: blur(7px); transition: filter .12s ease; cursor: pointer; }
.secondary.blurred:hover { filter: none; }

.w { cursor: pointer; border-radius: .25em; padding: 0 .04em; transition: background .1s, color .1s; }
.w:hover { background: rgba(255,255,255,.2); }
.w.saved { background: var(--highlight); color: var(--on-highlight); text-shadow: none; }
.w.active { background: #fff; color: #1c1c1e; text-shadow: none; }

.status {
  pointer-events: none; font-size: 12px; font-weight: 600; color: #e6e7eb;
  background: rgba(28,28,32,.85); padding: 4px 12px; border-radius: 999px;
}
.status:empty { display: none; }

/* Word lookup card */
.card {
  position: absolute; bottom: calc(100% + 12px); left: 50%; transform: translateX(-50%);
  min-width: 230px; max-width: 320px; pointer-events: auto;
  background: var(--card); color: var(--card-fg);
  border-radius: 24px; box-shadow: 0 20px 50px rgba(0,0,0,.5);
  padding: 16px 16px 14px; font-size: 14px; text-align: left; display: none;
}
.card.open { display: block; }
.card .top { display: flex; align-items: flex-start; gap: 10px; }
.card .hw { flex: 1; font-size: 24px; font-weight: 800; line-height: 1.15; word-break: break-word; }
.card .form { color: var(--card-dim); font-size: 13px; font-weight: 600; margin-top: 2px; }
.card .form:empty { display: none; }
.card .tr { color: var(--accent-text); font-size: 16px; font-weight: 600; min-height: 1.3em; margin: 4px 0 14px; line-height: 1.4; }
.card .tr.dim { color: var(--card-dim); font-weight: 500; font-style: italic; }
.card button { all: unset; cursor: pointer; text-align: center; font-weight: 700; }
.card button:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.card .save {
  display: block; width: 100%; box-sizing: border-box; height: 42px; line-height: 42px;
  border-radius: 21px; background: var(--accent); color: #fff; font-size: 14px;
}
.card .save:hover { filter: brightness(1.08); }
.card .save.on { background: var(--highlight); color: var(--on-highlight); }
.card .close {
  flex: none; width: 28px; height: 28px; border-radius: 14px; display: grid; place-items: center;
  background: var(--raised); color: var(--card-dim);
}
.card .close svg { width: 12px; height: 12px; }
.card .close:hover { color: var(--card-fg); }
`;

const GLYPHS = {
    previous: 'm15 6-6 6 6 6',
    next: 'm9 6 6 6-6 6',
    replay: 'M4 12a8 8 0 1 0 2.5-5.8M4 4v4.5h4.5',
    eye: 'M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12zM12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6z',
    pause: 'M8 5v14M16 5v14',
    loop: 'M17 3l3 3-3 3M4 11V9a3 3 0 0 1 3-3h13M7 21l-3-3 3-3M20 13v2a3 3 0 0 1-3 3H4',
    close: 'M6 6l12 12M18 6 6 18',
};

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
    private cardForm!: HTMLElement;
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
        const px = Math.max(12, Math.min(37, w * 0.0212)) * (this.settings.fontScale || 1);
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
        this.cardForm = el('div', 'form');
        this.cardTr = el('div', 'tr');
        this.cardSave = el('button', 'save') as HTMLButtonElement;

        const close = el('button', 'close') as HTMLButtonElement;
        close.setAttribute('aria-label', 'Close');
        close.appendChild(icon(GLYPHS.close, {stroke: 3.2}));
        close.addEventListener('click', () => this.closeCard());

        const top = el('div', 'top');
        top.append(this.cardWord, close);
        card.append(top, this.cardForm, this.cardTr, this.cardSave);
        return card;
    }

    private async openCard(span: HTMLElement, raw: string): Promise<void> {
        const word = norm(raw);
        this.activeWord?.classList.remove('active');
        this.activeWord = span;
        span.classList.add('active');

        this.cardWord.textContent = raw;
        this.cardForm.textContent = '';
        this.card.classList.add('open');
        // What gets saved: the meaning once it has arrived, never the
        // "Looking up…" placeholder.
        let meaning = '';

        const saved = this.hooks.isSaved(word);
        this.setSaveButton(saved);
        this.cardSave.onclick = async () => {
            if (this.hooks.isSaved(word)) {
                await this.hooks.removeWord(word);
                this.setSaveButton(false);
            } else {
                await this.hooks.saveWord(word, meaning);
                this.setSaveButton(true);
            }
            this.refreshSaved();
        };

        this.cardTr.textContent = 'Looking up…';
        this.cardTr.classList.add('dim');
        const out = await this.hooks.lookup(word);
        // The user may have clicked elsewhere while the lookup was in flight.
        if (this.activeWord !== span) return;
        if ('error' in out) {
            this.cardTr.textContent = `No translation: ${out.error}`;
            return;
        }
        meaning = out.meaning;
        // `holt` → `rausholen`: only worth a line when it adds something.
        if (out.form.toLowerCase() !== raw.toLowerCase()) this.cardForm.textContent = out.form;
        this.cardTr.textContent = out.meaning;
        this.cardTr.classList.remove('dim');
    }

    private setSaveButton(saved: boolean): void {
        this.cardSave.textContent = saved ? 'Saved — click to remove' : 'Save word';
        this.cardSave.classList.toggle('on', saved);
    }

    private closeCard(): void {
        this.card.classList.remove('open');
        this.activeWord?.classList.remove('active');
        this.activeWord = null;
    }

    /* ── Toolbar ────────────────────────────────────────────────────────────── */

    private buildBar(): HTMLElement {
        const bar = el('div', 'bar');

        const mk = (glyph: SVGElement, title: string, fn: () => void) => {
            const b = el('button') as HTMLButtonElement;
            b.appendChild(glyph);
            b.title = title;
            b.setAttribute('aria-label', title);
            b.addEventListener('click', e => {
                e.stopPropagation();
                fn();
            });
            bar.appendChild(b);
            return b;
        };

        mk(icon(GLYPHS.previous), 'Previous line  [', () => this.hooks.seekToCue(-1));
        mk(icon(GLYPHS.replay), 'Replay this line  \\', () => this.hooks.replayCue());
        mk(icon(GLYPHS.next), 'Next line  ]', () => this.hooks.seekToCue(1));
        bar.appendChild(el('div', 'sep'));

        const blur = mk(icon(GLYPHS.eye), 'Blur the translation until hovered  H', () => {
            this.hooks.patchSettings({blurSecondary: !this.settings.blurSecondary});
        });
        const pause = mk(icon(GLYPHS.pause, {stroke: 3}), 'Pause after each line  P', () => {
            this.hooks.patchSettings({autoPause: !this.settings.autoPause});
        });
        const loop = mk(icon(GLYPHS.loop), 'Loop this line  L', () => {
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

/** A stroked 24×24 glyph, built without markup like the rest of the overlay. */
function icon(d: string, {stroke = 2.2} = {}): SVGElement {
    const ns = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('fill', 'none');
    svg.setAttribute('stroke', 'currentColor');
    svg.setAttribute('stroke-width', String(stroke));
    svg.setAttribute('stroke-linecap', 'round');
    svg.setAttribute('stroke-linejoin', 'round');
    const path = document.createElementNS(ns, 'path');
    path.setAttribute('d', d);
    svg.appendChild(path);
    return svg;
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
