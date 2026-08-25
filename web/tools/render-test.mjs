/* Renders a Markdown file to standalone HTML using the real pipeline.
   Used to verify Phase 1 in a browser before any Swift exists. */
import { readFileSync, writeFileSync, mkdirSync, cpSync, existsSync } from 'node:fs';
import { dirname, resolve, join, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { render } from '../src/render/index.js';

const here = dirname(fileURLToPath(import.meta.url));
const webRoot = resolve(here, '..');

const argv = process.argv.slice(2);
const flags = argv.filter((a) => a.startsWith('--'));
const [inputArg, outputArg] = argv.filter((a) => !a.startsWith('--'));
if (!inputArg) {
  console.error('usage: node tools/render-test.mjs <input.md> [output.html] [--dark] [--unsafe]');
  process.exit(1);
}

const input = resolve(process.cwd(), inputArg);
const outDir = resolve(webRoot, 'dist/preview');
const output = outputArg
  ? resolve(process.cwd(), outputArg)
  : join(outDir, basename(input).replace(/\.md$/i, '') + (flags.includes('--dark') ? '.dark' : '') + '.html');

mkdirSync(dirname(output), { recursive: true });

const src = readFileSync(input, 'utf8');
const t0 = performance.now();
const { html, toc, frontMatter } = render(src, {
  unsafeHTML: flags.includes('--unsafe'),
  allowRemoteContent: false,
});
const ms = (performance.now() - t0).toFixed(1);

const css = ['styles/tokens.css', 'styles/fonts.css', 'styles/preview.css']
  .map((p) => readFileSync(join(webRoot, p), 'utf8'))
  .join('\n');
const katexCSS = readFileSync(join(webRoot, 'node_modules/katex/dist/katex.min.css'), 'utf8')
  .replace(/url\(fonts\//g, 'url(katex-fonts/');

/* Copy the font files the stylesheets reference. */
const fontDir = join(dirname(output), 'fonts');
mkdirSync(fontDir, { recursive: true });
const FONTS = [
  ['@fontsource/eb-garamond', ['400-normal', '400-italic', '500-normal', '500-italic'], 'eb-garamond'],
  ['@fontsource/inter', ['400-normal', '400-italic', '500-normal', '500-italic', '600-normal', '600-italic'], 'inter'],
  ['@fontsource/jetbrains-mono', ['400-normal', '400-italic', '500-normal', '700-normal'], 'jetbrains-mono'],
];
for (const [pkg, variants, prefix] of FONTS) {
  for (const v of variants) {
    const f = `${prefix}-latin-${v}.woff2`;
    const from = join(webRoot, 'node_modules', pkg, 'files', f);
    if (existsSync(from)) cpSync(from, join(fontDir, f));
  }
}
cpSync(join(webRoot, 'node_modules/katex/dist/fonts'), join(dirname(output), 'katex-fonts'), { recursive: true });

/* Local images referenced by the document resolve to mdapp://doc/... — for the
   browser test, point them back at the source directory. */
const docDir = dirname(input);
const fixed = html
  .replace(/mdapp:\/\/doc\//g, '')
  .replace(/src="mdapp:\/\/blocked\/([^"]*)"/g, (_, u) => `src="" data-blocked="${u}"`);

const theme = flags.includes('--dark') ? 'dark' : 'light';
const page = `<!doctype html>
<html lang="en" data-theme="${theme}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${basename(input)}</title>
<style>${katexCSS}</style>
<style>${css}</style>
<style>html,body{margin:0;padding:0;background:var(--doc-bg);}</style>
</head>
<body>
<article class="md-doc">
${fixed}
</article>
</body>
</html>`;

writeFileSync(output, page, 'utf8');

/* Copy the document's asset folder so relative images resolve. */
if (existsSync(join(docDir, 'assets'))) {
  cpSync(join(docDir, 'assets'), join(dirname(output), 'assets'), { recursive: true });
}

console.log(`rendered  ${input}`);
console.log(`      ->  ${output}`);
console.log(`   in ${ms} ms · ${html.length.toLocaleString()} chars · ${toc.length} headings`);
if (frontMatter) console.log(`   front matter keys: ${Object.keys(frontMatter).join(', ')}`);
