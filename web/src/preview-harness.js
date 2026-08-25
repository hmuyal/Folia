/* Development harness: exercises the real Preview class in a plain browser so
   the rendering pipeline can be verified before the Swift shell exists. */
import { Preview } from './preview/preview.js';

const mount = document.getElementById('harness');
const preview = new Preview(mount, {
  openExternal: (href) => console.log('[host] openExternal', href),
  openRelative: (href) => console.log('[host] openRelative', href),
  toggleTask:   (i, v) => console.log('[host] toggleTask', i, v),
});

const params = new URLSearchParams(location.search);
const file = params.get('doc') || 'kitchen-sink.md';
const dark = params.get('theme') === 'dark';

document.documentElement.dataset.theme = dark ? 'dark' : 'light';
preview.setTheme(dark);

const res = await fetch(`docs/${file}`);
const text = await res.text();
const info = preview.update(text);

window.__preview = preview;
window.__info = info;
console.log(`[harness] rendered ${file} in ${info.ms.toFixed(1)} ms · ${info.toc.length} headings`);
