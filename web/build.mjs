import * as esbuild from 'esbuild';
import { readFileSync, writeFileSync, mkdirSync, cpSync, existsSync, rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const out  = resolve(root, 'dist/web');
const watch = process.argv.includes('--watch');
const dev   = watch || process.argv.includes('--dev');

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

/* ---------------------------------------------------------------- fonts --- */
const fontDir = join(out, 'fonts');
mkdirSync(fontDir, { recursive: true });

const FONTS = [
  ['@fontsource/eb-garamond',   'eb-garamond',   ['400-normal', '400-italic', '500-normal', '500-italic']],
  ['@fontsource/inter',         'inter',         ['400-normal', '400-italic', '500-normal', '500-italic', '600-normal', '600-italic']],
  ['@fontsource/jetbrains-mono','jetbrains-mono',['400-normal', '400-italic', '500-normal', '700-normal']],
];
let fontCount = 0;
for (const [pkg, prefix, variants] of FONTS) {
  for (const v of variants) {
    const name = `${prefix}-latin-${v}.woff2`;
    const from = join(root, 'node_modules', pkg, 'files', name);
    if (existsSync(from)) { cpSync(from, join(fontDir, name)); fontCount++; }
    else console.warn(`  ! missing font ${name}`);
  }
}
/* KaTeX's stylesheet points at fonts/KaTeX_*.woff2 — same folder, no clash. */
cpSync(join(root, 'node_modules/katex/dist/fonts'), fontDir, { recursive: true });

/* ------------------------------------------------------------------ css --- */
const cssParts = [
  'node_modules/katex/dist/katex.min.css',
  'styles/tokens.css',
  'styles/fonts.css',
  'styles/preview.css',
  'styles/app.css',
].filter((p) => existsSync(join(root, p)));

function buildCSS() {
  const raw = cssParts.map((p) => `/* ==== ${p} ==== */\n${readFileSync(join(root, p), 'utf8')}`).join('\n');
  const result = esbuild.transformSync(raw, {
    loader: 'css',
    minify: !dev,
    target: ['safari17'],
  });
  writeFileSync(join(out, 'app.css'), result.code);
  return result.code.length;
}

/* ------------------------------------------------------------------- js --- */
const entries = ['src/main.js', 'src/preview-harness.js'].filter((p) => existsSync(join(root, p)));

const buildOptions = {
  entryPoints: entries.map((e) => join(root, e)),
  bundle: true,
  format: 'esm',
  splitting: true,          // lets mermaid land in its own lazily-fetched chunk
  outdir: out,
  target: ['safari17'],
  minify: !dev,
  sourcemap: dev ? 'inline' : false,
  logLevel: 'info',
  legalComments: 'none',
  define: { 'process.env.NODE_ENV': dev ? '"development"' : '"production"' },
};

/* ----------------------------------------------------------------- html --- */
function buildHTML() {
  for (const [file, entry, body] of [
    ['index.html', 'main.js', '<div id="app"></div>'],
    ['harness.html', 'preview-harness.js', '<div id="harness"></div>'],
  ]) {
    if (!existsSync(join(out, entry))) continue;
    writeFileSync(join(out, file), `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src folia: data: blob: http: https:; font-src folia: data: 'self'; style-src 'unsafe-inline' 'self' folia:; script-src 'self' folia: 'unsafe-eval'; connect-src 'self' folia:;">
<title>Folia</title>
<link rel="stylesheet" href="app.css">
</head>
<body>
${body}
<script type="module" src="${entry}"></script>
</body>
</html>
`);
  }
}

/* Sample documents for the harness (dev only). */
if (existsSync(join(root, '../samples'))) {
  cpSync(join(root, '../samples'), join(out, 'docs'), { recursive: true });
}

const cssBytes = buildCSS();
buildHTML();

if (watch) {
  const ctx = await esbuild.context(buildOptions);
  await ctx.watch();
  console.log(`watching…  css ${(cssBytes / 1024).toFixed(0)} KB · ${fontCount} fonts`);
} else {
  const result = await esbuild.build({ ...buildOptions, metafile: true });
  buildHTML();
  const sizes = Object.entries(result.metafile.outputs)
    .map(([f, m]) => [f.replace(/.*dist\/web\//, ''), m.bytes])
    .sort((a, b) => b[1] - a[1]);
  console.log('\nbundle:');
  for (const [f, b] of sizes.slice(0, 8)) console.log(`  ${(b / 1024).toFixed(0).padStart(6)} KB  ${f}`);
  console.log(`  ${(cssBytes / 1024).toFixed(0).padStart(6)} KB  app.css`);
  console.log(`  ${fontCount} app fonts + KaTeX fonts copied`);
}
