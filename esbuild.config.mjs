import { build, context } from 'esbuild';
import { copyFileSync, watch as fsWatch } from 'fs';

const isWatch = process.argv.includes('--watch');

const common = {
  bundle: true,
  minify: false,
  sourcemap: true,
  target: 'chrome120',
};

const configs = [
  { ...common, entryPoints: ['extension/src/content.ts'], outfile: 'dist/extension/content.js' },
  { ...common, entryPoints: ['extension/src/injected.ts'], outfile: 'dist/extension/injected.js' },
  { ...common, entryPoints: ['extension/src/background.ts'], outfile: 'dist/extension/background.js' },
  { ...common, entryPoints: ['extension/src/popup.ts'], outfile: 'dist/extension/popup.js' },
];

function copyStatic() {
  copyFileSync('extension/manifest.json', 'dist/extension/manifest.json');
  copyFileSync('extension/overlay.css', 'dist/extension/overlay.css');
  copyFileSync('extension/src/popup.html', 'dist/extension/popup.html');
}

if (isWatch) {
  for (const config of configs) {
    const ctx = await context(config);
    await ctx.watch();
  }
  copyStatic();
  fsWatch('extension', { recursive: true }, () => copyStatic());
  console.log('watching... static files auto-copied');
} else {
  await Promise.all(configs.map(c => build(c)));
  copyStatic();
  console.log('built.');
}
