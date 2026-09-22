import {MediaInfo} from '../../shared/types';
import {Adapter} from './adapter';
import {ard} from './ard';
import {zdf} from './zdf';
import {youtube} from './youtube';

export type {Adapter} from './adapter';
export {pickArdSubtitleUrl} from './ard';
export {parseYtPayload} from './youtube';

/** Add a new site by writing its adapter alongside these and listing it here. */
const ADAPTERS: Adapter[] = [ard, zdf, youtube];

export function adapterFor(host = location.hostname): Adapter | null {
    return ADAPTERS.find(a => a.matches(host)) || null;
}

export function mediaInfo(adapter: Adapter | null): MediaInfo {
    const site = location.hostname.replace(/^www\./, '');
    return {
        title: adapter?.title() || document.title,
        site,
        url: location.href,
        key: `${site}:${adapter?.mediaKey() || location.pathname}`,
    };
}
