/**
 * Generates the extension's PNG icons with no image dependencies.
 *
 * The same mark as the apps (desktop/make-icon.swift): a violet tile holding a
 * speech bubble with a highlighted word. Each pixel is supersampled so the
 * edges stay smooth down to 16px.
 */
import {deflateSync} from 'zlib';
import {mkdirSync, writeFileSync} from 'fs';

const OUT = 'icons';
const SAMPLES = 4;

const TOP = [0x8a, 0x6b, 0xff];
const BOTTOM = [0x5a, 0x36, 0xe6];
const WHITE = [0xff, 0xff, 0xff];
const YELLOW = [0xff, 0xc9, 0x33];
const LILAC = [0xcf, 0xc4, 0xff];

// Shapes in the app icon's 1024 space (y down), whose tile spans 100…924.
// The toolbar icon has no margin, so everything is scaled out to fill it.
const K = 1024 / 824;
const at = v => (v - 100) * K;

const roundRect = (x0, y0, x1, y1, r) => ({x0: at(x0), y0: at(y0), x1: at(x1), y1: at(y1), r: r * K});
const BUBBLE = roundRect(252, 300, 772, 680, 120);
const TAIL = [[318, 624], [282, 762], [452, 664]].map(([x, y]) => [at(x), at(y)]);
const WORD = roundRect(330, 388, 580, 464, 38);
const SENTENCE = roundRect(330, 528, 694, 586, 29);

function inRoundRect(x, y, {x0, y0, x1, y1, r}) {
    if (x < x0 || x > x1 || y < y0 || y > y1) return false;
    const dx = Math.max(x0 + r - x, 0, x - (x1 - r));
    const dy = Math.max(y0 + r - y, 0, y - (y1 - r));
    return dx * dx + dy * dy <= r * r;
}

function inTriangle(x, y, [[ax, ay], [bx, by], [cx, cy]]) {
    const s = (px, py, qx, qy, rx, ry) => (px - rx) * (qy - ry) - (qx - rx) * (py - ry);
    const d1 = s(x, y, ax, ay, bx, by), d2 = s(x, y, bx, by, cx, cy), d3 = s(x, y, cx, cy, ax, ay);
    return !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0));
}

/** The colour at one point of the 1024 canvas, or null outside the tile. */
function sample(x, y) {
    if (!inRoundRect(x, y, {x0: 0, y0: 0, x1: 1024, y1: 1024, r: 225})) return null;
    if (inRoundRect(x, y, WORD)) return YELLOW;
    if (inRoundRect(x, y, SENTENCE)) return LILAC;
    if (inRoundRect(x, y, BUBBLE) || inTriangle(x, y, TAIL)) return WHITE;
    const t = y / 1024;
    return TOP.map((c, i) => c + (BOTTOM[i] - c) * t);
}

function pixel(px, py, size) {
    const acc = [0, 0, 0, 0];
    for (let sy = 0; sy < SAMPLES; sy++) {
        for (let sx = 0; sx < SAMPLES; sx++) {
            const c = sample(((px + (sx + 0.5) / SAMPLES) / size) * 1024, ((py + (sy + 0.5) / SAMPLES) / size) * 1024);
            if (!c) continue;
            acc[0] += c[0];
            acc[1] += c[1];
            acc[2] += c[2];
            acc[3] += 1;
        }
    }
    if (acc[3] === 0) return [0, 0, 0, 0];
    return [acc[0] / acc[3], acc[1] / acc[3], acc[2] / acc[3], (255 * acc[3]) / (SAMPLES * SAMPLES)].map(Math.round);
}

const CRC_TABLE = (() => {
    const t = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
        let c = n;
        for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
        t[n] = c;
    }
    return t;
})();

function crc32(buf) {
    let c = -1;
    for (const b of buf) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
    return (c ^ -1) >>> 0;
}

function chunk(type, data) {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(body));
    return Buffer.concat([len, body, crc]);
}

function png(size) {
    const raw = Buffer.alloc(size * (size * 4 + 1));
    let o = 0;
    for (let y = 0; y < size; y++) {
        raw[o++] = 0; // filter: none
        for (let x = 0; x < size; x++) {
            for (const v of pixel(x, y, size)) raw[o++] = v;
        }
    }

    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(size, 0);
    ihdr.writeUInt32BE(size, 4);
    ihdr[8] = 8;  // bit depth
    ihdr[9] = 6;  // colour type: RGBA
    return Buffer.concat([
        Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
        chunk('IHDR', ihdr),
        chunk('IDAT', deflateSync(raw, {level: 9})),
        chunk('IEND', Buffer.alloc(0)),
    ]);
}

mkdirSync(OUT, {recursive: true});
for (const size of [16, 32, 48, 128]) {
    writeFileSync(`${OUT}/${size}.png`, png(size));
}
console.log(`icons written → ${OUT}`);
