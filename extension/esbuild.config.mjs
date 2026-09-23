import { build, context } from 'esbuild';
import { copyFileSync, mkdirSync, cpSync, existsSync } from 'fs';

const watch = process.argv.includes('--watch');
// Dev builds keep the local log-server mirroring; production compiles it out.
const dev = watch || process.argv.includes('--dev');

// The folder you point "Load unpacked" at. It sits beside the smoke-test bundle
// rather than alongside it in one directory, so nothing but the extension's own
// files end up in what the browser loads.
const OUT = 'dist/unpacked';

const common = {
  bundle: true,
  format: 'iife',
  target: 'chrome120',
  sourcemap: dev,
  minify: !dev,
  legalComments: 'none',
  define: { __MT_DEV__: String(dev) },
};

// Each entry maps to one file named in the manifest.
const entries = [
  ['src/content.ts', `${OUT}/content.js`],
  ['src/capture/injected.ts', `${OUT}/injected.js`],
  ['src/background.ts', `${OUT}/background.js`],
  ['src/ui/popup.ts', `${OUT}/popup.js`],
];

const configs = entries.map(([entryPoint, outfile]) => ({
  ...common,
  entryPoints: [entryPoint],
  outfile,
}));

function copyStatic() {
  mkdirSync(OUT, { recursive: true });
  copyFileSync('manifest.json', `${OUT}/manifest.json`);
  copyFileSync('src/ui/popup.html', `${OUT}/popup.html`);
  if (existsSync('icons')) {
    cpSync('icons', `${OUT}/icons`, { recursive: true });
  }
}

if (watch) {
  for (const config of configs) {
    const ctx = await context(config);
    await ctx.watch();
  }
  copyStatic();
  const { watch: fsWatch } = await import('fs');
  fsWatch('src', { recursive: true }, () => copyStatic());
  console.log(`watching (dev build) → ${OUT}`);
} else {
  await Promise.all(configs.map(c => build(c)));
  copyStatic();
  console.log(`built ${dev ? 'dev' : 'production'} → ${OUT}`);
}
