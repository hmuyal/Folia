import TurndownService from 'turndown';
import { gfm } from 'turndown-plugin-gfm';
import { insertImage } from './commands.js';
import { host } from '../bridge/host.js';

/* Paste and drop handling: HTML becomes Markdown, images are written to disk
   by the host and referenced relatively, and a URL pasted over a selection
   turns that selection into a link. */

let turndown = null;
function converter() {
  if (turndown) return turndown;
  turndown = new TurndownService({
    headingStyle: 'atx',
    hr: '---',
    bulletListMarker: '-',
    codeBlockStyle: 'fenced',
    fence: '```',
    emDelimiter: '*',
    strongDelimiter: '**',
    linkStyle: 'inlined',
  });
  turndown.use(gfm);

  // Keep a few things the default rules would flatten.
  turndown.addRule('keepUnderline', {
    filter: ['u', 'ins'],
    replacement: (content) => `++${content}++`,
  });
  turndown.addRule('keepMark', {
    filter: ['mark'],
    replacement: (content) => `==${content}==`,
  });
  turndown.addRule('stripEmptyAnchors', {
    filter: (node) => node.nodeName === 'A' && !node.getAttribute('href'),
    replacement: (content) => content,
  });
  return turndown;
}

export function htmlToMarkdown(html) {
  try {
    return converter().turndown(html).replace(/\n{3,}/g, '\n\n').trim();
  } catch (err) {
    host.log('warn', `HTML to Markdown failed: ${err.message}`);
    return null;
  }
}

const URL_RE = /^(https?:\/\/|mailto:)\S+$/i;

/** Handles a paste event. Returns true when it consumed the event. */
export function handlePaste(view, event) {
  const data = event.clipboardData;
  if (!data) return false;

  // 1. An image on the clipboard -> ask the host to save it next to the doc.
  const imageItem = [...(data.items || [])].find((i) => i.type.startsWith('image/'));
  if (imageItem) {
    const file = imageItem.getAsFile();
    if (file) { void saveAndInsert(view, file); return true; }
  }

  const text = data.getData('text/plain');

  // 2. A URL pasted over a selection becomes a link around it.
  if (text && URL_RE.test(text.trim())) {
    const range = view.state.selection.main;
    if (!range.empty) {
      const label = view.state.sliceDoc(range.from, range.to);
      if (!/[\n]/.test(label)) {
        view.dispatch({
          changes: { from: range.from, to: range.to, insert: `[${label}](${text.trim()})` },
          scrollIntoView: true,
        });
        return true;
      }
    }
  }

  // 3. Rich HTML -> Markdown, but only when it is genuinely richer than the
  //    plain-text flavour (copying from a code editor produces both).
  const html = data.getData('text/html');
  if (html && html.trim()) {
    const markdown = htmlToMarkdown(html);
    if (markdown && markdown !== text?.trim() && looksRicher(markdown, text)) {
      const range = view.state.selection.main;
      view.dispatch({
        changes: { from: range.from, to: range.to, insert: markdown },
        scrollIntoView: true,
      });
      return true;
    }
  }

  return false;   // fall through to CodeMirror's own paste
}

function looksRicher(markdown, plain) {
  if (!plain) return true;
  // Markdown syntax that the plain-text flavour did not already contain.
  return /(^|\n)#{1,6}\s|\*\*|\[.+\]\(|^[-*]\s|\|.*\|/m.test(markdown);
}

export function handleDrop(view, event) {
  const files = [...(event.dataTransfer?.files || [])];
  if (!files.length) return false;

  const pos = view.posAtCoords({ x: event.clientX, y: event.clientY });
  if (pos != null) {
    view.dispatch({ selection: { anchor: pos } });
  }

  const images = files.filter((f) => f.type.startsWith('image/'));
  if (images.length) {
    void (async () => { for (const f of images) await saveAndInsert(view, f); })();
    return true;
  }

  // A dropped Markdown file opens rather than embeds.
  const doc = files.find((f) => /\.(md|markdown|txt|mdx|qmd|rmd)$/i.test(f.name));
  if (doc) { host.openRelative(doc.name); return true; }

  return false;
}

async function saveAndInsert(view, file) {
  const base64 = await fileToBase64(file);
  if (!base64) return;

  const result = await host.request('saveImage', {
    data: base64,
    suggestedName: file.name || 'pasted-image',
    mimeType: file.type,
  });

  if (result?.path) {
    insertImage(view, result.path, altFromName(result.path));
  } else {
    // No host (dev harness) or the save failed — inline it so nothing is lost.
    insertImage(view, `data:${file.type};base64,${base64}`, 'pasted image');
  }
}

function altFromName(path) {
  const name = path.split('/').pop() || '';
  return name.replace(/\.[^.]+$/, '').replace(/[-_]+/g, ' ');
}

function fileToBase64(file) {
  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = String(reader.result || '');
      resolve(result.slice(result.indexOf(',') + 1));
    };
    reader.onerror = () => resolve(null);
    reader.readAsDataURL(file);
  });
}
