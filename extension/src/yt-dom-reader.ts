import { Cue } from './types';
import { log } from './logger';

export class YTDomCaptionReader {
  private observer: MutationObserver | null = null;
  private video: HTMLVideoElement;
  private cues: Cue[] = [];
  private currentText = '';
  private captionStart = 0;
  private onCuesUpdated: ((cues: Cue[]) => void) | null = null;

  constructor(video: HTMLVideoElement) {
    this.video = video;
  }

  start(callback: (cues: Cue[]) => void) {
    this.onCuesUpdated = callback;
    this.cues = [];

    const container = document.querySelector('.ytp-caption-window-container');
    if (!container) {
      log.info('YT DOM reader: waiting for caption container...');
      this.waitForContainer(callback);
      return;
    }

    this.attachObserver(container);
  }

  private waitForContainer(callback: (cues: Cue[]) => void) {
    const bodyObserver = new MutationObserver(() => {
      const container = document.querySelector('.ytp-caption-window-container');
      if (container) {
        bodyObserver.disconnect();
        log.info('YT DOM reader: caption container found');
        this.attachObserver(container);
      }
    });
    bodyObserver.observe(document.body, { childList: true, subtree: true });
  }

  private attachObserver(container: Element) {
    this.observer = new MutationObserver(() => {
      const segments = container.querySelectorAll('.ytp-caption-segment');
      const text = Array.from(segments).map(s => s.textContent?.trim()).filter(Boolean).join(' ');

      if (text && text !== this.currentText) {
        if (this.currentText) {
          this.cues.push({
            start: this.captionStart,
            end: this.video.currentTime,
            text: this.currentText,
          });
        }
        this.currentText = text;
        this.captionStart = this.video.currentTime;
        this.onCuesUpdated?.(this.cues);
      } else if (!text && this.currentText) {
        this.cues.push({
          start: this.captionStart,
          end: this.video.currentTime,
          text: this.currentText,
        });
        this.currentText = '';
        this.onCuesUpdated?.(this.cues);
      }
    });

    this.observer.observe(container, {
      childList: true,
      subtree: true,
      characterData: true,
    });

    log.info('YT DOM reader: observing caption changes');
  }

  stop() {
    this.observer?.disconnect();
    this.observer = null;
  }

  getCurrentText(): string {
    const container = document.querySelector('.ytp-caption-window-container');
    if (!container) return '';
    const segments = container.querySelectorAll('.ytp-caption-segment');
    return Array.from(segments).map(s => s.textContent?.trim()).filter(Boolean).join(' ');
  }
}
