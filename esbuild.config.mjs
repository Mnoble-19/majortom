import { build, context } from 'esbuild';
import { copyFileSync, mkdirSync, cpSync, existsSync } from 'fs';

const watch = process.argv.includes('--watch');
// Dev builds keep the local log-server mirroring; production compiles it out.
const dev = watch || process.argv.includes('--dev');

const OUT = 'dist/extension';

const common = {
  bundle: true,
  format: 'iife',
  target: 'chrome120',
  sourcemap: dev,
  minify: !dev,
  legalComments: 'none',
  define: { __MT_DEV__: String(dev) },
};

const entries = [
  ['extension/src/content.ts', `${OUT}/content.js`],
  ['extension/src/injected.ts', `${OUT}/injected.js`],
  ['extension/src/background.ts', `${OUT}/background.js`],
  ['extension/src/popup.ts', `${OUT}/popup.js`],
];

const configs = entries.map(([entryPoint, outfile]) => ({
  ...common,
  entryPoints: [entryPoint],
  outfile,
}));

function copyStatic() {
  mkdirSync(OUT, { recursive: true });
  copyFileSync('extension/manifest.json', `${OUT}/manifest.json`);
  copyFileSync('extension/src/popup.html', `${OUT}/popup.html`);
  if (existsSync('extension/icons')) {
    cpSync('extension/icons', `${OUT}/icons`, { recursive: true });
  }
}

if (watch) {
  for (const config of configs) {
    const ctx = await context(config);
    await ctx.watch();
  }
  copyStatic();
  const { watch: fsWatch } = await import('fs');
  fsWatch('extension', { recursive: true }, () => copyStatic());
  console.log(`watching (dev build) → ${OUT}`);
} else {
  await Promise.all(configs.map(c => build(c)));
  copyStatic();
  console.log(`built ${dev ? 'dev' : 'production'} → ${OUT}`);
}
