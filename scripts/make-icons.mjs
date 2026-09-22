/**
 * Generates the extension's PNG icons with no image dependencies.
 *
 * The mark is two stacked bars — a bright one over a dimmer one — which is the
 * dual-subtitle idea reduced to something still legible at 16px.
 */
import {deflateSync} from 'zlib';
import {mkdirSync, writeFileSync} from 'fs';

const OUT = 'extension/icons';

const BG = [0x14, 0x16, 0x1e];
const PRIMARY = [0xff, 0xff, 0xff];
const SECONDARY = [0x7e, 0xc8, 0xe3];

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
    const px = (x, y) => {
        const r = size * 0.22; // corner radius
        // Rounded-square mask
        const cx = Math.min(x, size - 1 - x), cy = Math.min(y, size - 1 - y);
        if (cx < r && cy < r) {
            const dx = r - cx, dy = r - cy;
            if (dx * dx + dy * dy > r * r) return null; // transparent corner
        }

        const barH = Math.max(1, Math.round(size * 0.115));
        const gap = Math.max(1, Math.round(size * 0.1));
        const topY = Math.round(size * 0.36);
        const botY = topY + barH + gap;

        const inset1 = Math.round(size * 0.19);
        const inset2 = Math.round(size * 0.29);

        if (y >= topY && y < topY + barH && x >= inset1 && x < size - inset1) return PRIMARY;
        if (y >= botY && y < botY + barH && x >= inset2 && x < size - inset2) return SECONDARY;
        return BG;
    };

    const raw = Buffer.alloc(size * (size * 4 + 1));
    let o = 0;
    for (let y = 0; y < size; y++) {
        raw[o++] = 0; // filter: none
        for (let x = 0; x < size; x++) {
            const c = px(x, y);
            if (c === null) {
                raw[o++] = 0;
                raw[o++] = 0;
                raw[o++] = 0;
                raw[o++] = 0;
            } else {
                raw[o++] = c[0];
                raw[o++] = c[1];
                raw[o++] = c[2];
                raw[o++] = 255;
            }
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
