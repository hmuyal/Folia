/**
 * Builds a single self-contained HTML file: stylesheet, fonts and images all
 * inlined, so the export opens correctly with no network and no sidecar files.
 *
 * Fonts are the expensive part, so only the faces the document can actually
 * use are embedded — and KaTeX's only when there is maths on the page.
 */

import { host, isHosted } from '../bridge/host.js';

const CORE_FONTS = [
  'inter-latin-400-normal.woff2',
  'inter-latin-400-italic.woff2',
  'inter-latin-500-normal.woff2',
  'inter-latin-600-normal.woff2',
  'eb-garamond-latin-400-normal.woff2',
  'eb-garamond-latin-400-italic.woff2',
  'jetbrains-mono-latin-400-normal.woff2',
  'jetbrains-mono-latin-700-normal.woff2',
];

/*
 * Assets are read through the host, not fetch(): WKWebView does not resolve
 * fetch() against a custom URL scheme, so a fetch of folia://… never settles.
 * Swift already owns the filesystem, so it does the reading and base64-ing.
 * The fetch path stays for the browser dev harness.
 */

async function readAssetsAsDataURIs(urls) {
  const unique = [...new Set(urls)].filter(Boolean);
  if (!unique.length) return {};

  if (isHosted) {
    return (await host.request('inlineAssets', { urls: unique })) || {};
  }

  const out = {};
  await Promise.all(unique.map(async (url) => {
    const dataURI = await fetchAsDataURI(url);
    if (dataURI) out[url] = dataURI;
  }));
  return out;
}

async function fetchAsDataURI(url) {
  try {
    const response = await fetch(url);
    if (!response.ok) return null;
    const blob = await response.blob();
    return await new Promise((resolve) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result));
      reader.onerror = () => resolve(null);
      reader.readAsDataURL(blob);
    });
  } catch {
    return null;
  }
}

async function readAssetText(url) {
  if (isHosted) {
    const result = await host.request('readAsset', { url });
    return result?.text ?? '';
  }
  try {
    const response = await fetch(url);
    return response.ok ? await response.text() : '';
  } catch {
    return '';
  }
}

/**
 * Rewrites @font-face rules to inline data URIs.
 *
 * Works per-rule rather than per-url because stylesheets list several formats
 * for one face (KaTeX ships woff2 + woff + ttf). Only the woff2 is embedded;
 * the other two would triple the file for no benefit, and a rule left pointing
 * at a stripped url() makes the browser retry forever. Faces we do not keep
 * have their whole rule removed.
 */
async function inlineFonts(css, { keep }) {
  const faceRule = /@font-face\s*\{[^}]*\}/g;
  const urlRef = /url\((?:"|')?(fonts\/[^)"']+)(?:"|')?\)/g;

  const rules = css.match(faceRule) || [];
  const wanted = new Set();
  for (const rule of rules) {
    for (const [, path] of rule.matchAll(urlRef)) {
      if (path.endsWith('.woff2') && keep(path.split('/').pop())) wanted.add(path);
    }
  }

  const resolved = await readAssetsAsDataURIs([...wanted].map((p) => `folia://asset/${p}`));

  return css.replace(faceRule, (rule) => {
    const paths = [...rule.matchAll(urlRef)].map(([, path]) => path);
    const target = paths.find((p) => wanted.has(p));
    const dataURI = target && resolved[`folia://asset/${target}`];
    if (!dataURI) return '';                       // face not embedded: drop the rule
    return rule.replace(/src\s*:[^;}]*/, `src:url("${dataURI}") format("woff2")`);
  });
}

/** Replaces every <img src> with an inline data URI. */
async function inlineImages(root) {
  const images = [...root.querySelectorAll('img')];
  const sources = images
    .map((img) => img.getAttribute('src') || '')
    .filter((src) => src && !src.startsWith('data:'));

  const resolved = await readAssetsAsDataURIs(sources);

  for (const img of images) {
    const src = img.getAttribute('src') || '';
    if (!src || src.startsWith('data:')) continue;
    if (resolved[src]) img.setAttribute('src', resolved[src]);
    else img.removeAttribute('src');   // an unresolvable src would 404 forever
  }
}

function escapeHTML(s) {
  return String(s).replace(/[&<>"]/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}

/**
 * @param {HTMLElement} source   the live .md-doc element
 * @param {object}      options  { title, theme, forPrint, customCSS }
 */
export async function buildStandaloneHTML(source, {
  title = 'Document',
  theme = 'light',
  forPrint = false,
  customCSS = '',
} = {}) {
  // Work on a clone so the live document is never mutated.
  const clone = source.cloneNode(true);

  // Interactive affordances mean nothing in a static file.
  clone.querySelectorAll('.code-window__copy').forEach((el) => el.remove());
  clone.querySelectorAll('.heading-anchor').forEach((el) => el.remove());
  clone.querySelectorAll('input[type="checkbox"]').forEach((el) => {
    el.setAttribute('disabled', '');
  });
  clone.querySelectorAll('[data-line]').forEach((el) => el.removeAttribute('data-line'));

  await inlineImages(clone);

  const hasMath = Boolean(clone.querySelector('.katex'));
  let css = await readAssetText('folia://asset/app.css');
  css = await inlineFonts(css, {
    keep: (file) => CORE_FONTS.includes(file) || (hasMath && file.startsWith('KaTeX_')),
  });

  // The shell's own layout rules would fight a plain document.
  css += `
/* standalone overrides */
html, body { height: auto; overflow: visible; user-select: text; }
body { background: var(--doc-bg); }
.md-doc { min-height: 0; padding-top: 40px; }
`;
  if (forPrint) {
    css += `
@page { margin: 18mm 16mm; }
html, body { background: #fff; }
.md-doc { --doc-bg: #fff; padding: 0; }
`;
  }
  if (customCSS.trim()) css += `\n/* custom */\n${customCSS}\n`;

  return `<!doctype html>
<html lang="en" data-theme="${theme === 'dark' ? 'dark' : 'light'}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="generator" content="Folia">
<title>${escapeHTML(title)}</title>
<style>
${css}
</style>
</head>
<body>
<article class="md-doc">
${clone.innerHTML}
</article>
</body>
</html>
`;
}
