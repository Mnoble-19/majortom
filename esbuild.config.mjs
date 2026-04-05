import { build, context } from 'esbuild';

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

if (isWatch) {
  for (const config of configs) {
    const ctx = await context(config);
    await ctx.watch();
  }
  console.log('watching...');
} else {
  await Promise.all(configs.map(c => build(c)));
  console.log('built.');
}
