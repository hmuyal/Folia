import { Layout } from './app/layout.js';
import { ScrollSync } from './app/sync.js';
import { Editor } from './editor/editor.js';
import { Preview } from './preview/preview.js';
import { buildStandaloneHTML } from './export/standalone.js';
import { host } from './bridge/host.js';
import { nextFrame } from './app/nextFrame.js';
import { slugify } from './render/index.js';

const root = document.getElementById('app');
const layout = new Layout(root, {
  onRatioChange: (ratio) => host.request('setSplitRatio', { ratio }),
});

let currentDocumentID = '';
let renderTimer = null;
let statsTimer = null;
let lastRenderedText = null;

const preview = new Preview(layout.previewHost, {
  openExternal: (href) => host.openExternal(href),
  openRelative: (href) => host.openRelative(href),
  toggleTask:   (index, checked) => host.toggleTask(index, checked),
});

const editor = new Editor(layout.editorHost, {
  onChange: (text, cursorLine) => {
    host.textChanged(currentDocumentID, text, cursorLine);
    scheduleRender();
    scheduleStats(text);
  },
  onCursor: (line) => host.cursor(line),
  onScroll: (topLine) => sync.fromEditor(topLine),
});

const sync = new ScrollSync({
  editor,
  preview,
  previewScroller: layout.previewPane,
});

/* --- rendering ------------------------------------------------------------ */

/* Typing should not re-parse on every keystroke, but the preview must not feel
   laggy either. Short documents render immediately; long ones settle first. */
function scheduleRender() {
  clearTimeout(renderTimer);
  const length = editor.view.state.doc.length;
  const delay = length < 20_000 ? 40 : length < 200_000 ? 120 : 300;
  renderTimer = setTimeout(renderNow, delay);
}

function renderNow() {
  const text = editor.text;
  if (text === lastRenderedText) return;
  lastRenderedText = text;

  const topLine = sync.owner === 'preview' ? null : editor.topLine();
  const result = preview.update(text);

  host.outline((result.toc || []).map((h) => ({
    level: h.level,
    text: h.text,
    slug: h.id || slugify(h.text),
    line: h.line,
  })));

  // The line index just changed; keep the preview where the editor is looking.
  if (topLine != null) sync.realign(topLine);
}

function scheduleStats(text) {
  clearTimeout(statsTimer);
  statsTimer = setTimeout(() => sendStats(text), 350);
}

function sendStats(text) {
  // Strip the things a reader does not read before counting.
  const prose = text
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`[^`]*`/g, ' ')
    .replace(/^---[\s\S]*?^---/m, ' ')
    .replace(/!\[[^\]]*\]\([^)]*\)/g, ' ')
    .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/[#>*_~`|-]/g, ' ');

  const words = (prose.match(/[\p{L}\p{N}][\p{L}\p{N}'’-]*/gu) || []).length;
  host.stats({
    words,
    characters: text.length,
    readingMinutes: words > 0 ? Math.max(1, Math.round(words / 225)) : 0,
  });
}

/* --- the API Swift calls -------------------------------------------------- */

const MDApp = {
  setDocument({ id, text, path, cursorLine = 0, scrollLine = 0 }) {
    currentDocumentID = id;
    lastRenderedText = null;
    document.title = path ? path.split('/').pop() : 'Untitled';
    editor.setText(text ?? '', { cursorLine, scrollLine });
    renderNow();
    sendStats(text ?? '');
    if (scrollLine > 0) {
      requestAnimationFrame(() => sync.realign(scrollLine));
    } else {
      layout.previewPane.scrollTop = 0;
    }
  },

  replaceText(text) {
    editor.replaceText(text);
    renderNow();
    sendStats(text);
  },

  getText() { return editor.text; },

  setOptions(options) {
    preview.setOptions(options);
    if (options.previewFontSize) {
      document.documentElement.style.setProperty('--doc-font-size', `${options.previewFontSize}px`);
    }
    if (options.measure) {
      document.documentElement.style.setProperty('--measure', `${options.measure}px`);
      document.documentElement.style.setProperty('--measure-wide',
        `${Math.round(options.measure * 1.45)}px`);
    }
    lastRenderedText = null;
    renderNow();
  },

  setTheme(theme) {
    document.documentElement.dataset.theme = theme === 'dark' ? 'dark' : 'light';
    preview.setTheme(theme === 'dark');
  },

  setViewMode(mode) {
    layout.setMode(mode);
    // The preview was display:none in source mode, so its line index is stale.
    if (mode !== 'source') {
      requestAnimationFrame(() => preview.buildLineIndex());
    }
    if (mode === 'source' || mode === 'split') editor.focus();
  },

  setEditorPrefs(prefs) {
    editor.setPrefs({
      fontSize:    prefs.fontSize,
      tabWidth:    prefs.tabWidth,
      lineNumbers: prefs.lineNumbers,
      wrap:        prefs.wrap,
      typewriter:  prefs.typewriter,
      vimMode:     prefs.vim,
    });
    if (prefs.focus != null) root.dataset.focus = prefs.focus ? '1' : '0';
    if (prefs.scrollSync != null) sync.setEnabled(Boolean(prefs.scrollSync));
    if (prefs.splitRatio != null) layout.setRatio(prefs.splitRatio);
    if (prefs.previewFontSize) {
      document.documentElement.style.setProperty('--doc-font-size', `${prefs.previewFontSize}px`);
    }
    if (prefs.measure) {
      document.documentElement.style.setProperty('--measure', `${prefs.measure}px`);
      document.documentElement.style.setProperty('--measure-wide',
        `${Math.round(prefs.measure * 1.45)}px`);
    }
  },

  setCustomCSS(css) {
    let tag = document.getElementById('mdapp-custom-css');
    if (!tag) {
      tag = document.createElement('style');
      tag.id = 'mdapp-custom-css';
      document.head.appendChild(tag);
    }
    tag.textContent = css || '';
  },

  command(name) {
    // A couple of commands belong to the preview, not the editor.
    if (name === 'scrollTop') { layout.previewPane.scrollTop = 0; return; }
    editor.run(name);
  },

  scrollToLine(line) {
    editor.scrollToLine(line, { center: true });
    sync.claim('editor');
    layout.previewPane.scrollTop = preview.offsetForLine(line);
  },

  async exportHTML(standalone = true, options = {}) {
    // Make sure what we export matches what is on screen.
    renderNow();
    await nextFrame();
    if (!standalone) return layout.previewHost.innerHTML;

    return buildStandaloneHTML(layout.previewHost, {
      title: document.title,
      theme: document.documentElement.dataset.theme,
      forPrint: Boolean(options.print),
      customCSS: document.getElementById('mdapp-custom-css')?.textContent || '',
    });
  },
};

window.MDApp = MDApp;

/* Cmd-S is handled by the host menu, but the WebView sees it first when the
   editor has focus. */
window.addEventListener('keydown', (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key === 's') {
    event.preventDefault();
    host.requestSave();
  }
});

/* Re-measure breakout and the line index when the window resizes. */
let resizeTimer = null;
window.addEventListener('resize', () => {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(() => {
    preview.buildLineIndex();
  }, 120);
});

host.ready();
