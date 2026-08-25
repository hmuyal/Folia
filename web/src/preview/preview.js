import { render } from '../render/index.js';
import { DEFAULT_OPTIONS } from '../render/options.js';
import { sanitizeHTML } from './sanitize.js';
import { renderMermaid, resetMermaid } from './mermaid.js';
import {
  resolveRawImages, markBrokenImages, applyConditionalBreakout,
  bindCopyButtons, bindLinks, bindTaskLists,
} from './postprocess.js';

/**
 * Owns the rendered document: markdown in, live DOM out, plus the line map
 * that scroll sync rides on.
 */
export class Preview {
  constructor(container, host = {}) {
    this.el = container;
    this.host = host;
    this.options = { ...DEFAULT_OPTIONS };
    this.dark = false;
    this.toc = [];
    this.lineIndex = [];
    this._renderToken = 0;

    this.el.classList.add('md-doc');
    bindCopyButtons(this.el);
    bindLinks(this.el, host);
    bindTaskLists(this.el, host);
  }

  setOptions(partial) {
    this.options = { ...this.options, ...partial };
  }

  setTheme(dark) {
    if (this.dark === dark) return;
    this.dark = dark;
    resetMermaid(this.el);
    renderMermaid(this.el, { dark }).catch(() => {});
  }

  /** Renders markdown into the container. Returns { toc, frontMatter, ms }. */
  update(markdown) {
    const started = performance.now();
    const token = ++this._renderToken;

    const { html, toc, frontMatter } = render(markdown, this.options);
    const safe = this.options.sanitizeHTML ? sanitizeHTML(html) : html;

    this.el.innerHTML = safe;
    this.toc = toc;

    resolveRawImages(this.el, this.options);
    markBrokenImages(this.el);
    applyConditionalBreakout(this.el);
    this.buildLineIndex();

    if (this.options.mermaid) {
      renderMermaid(this.el, { dark: this.dark })
        .then((n) => {
          /* Diagrams change their own width, so re-measure breakout after. */
          if (n && token === this._renderToken) applyConditionalBreakout(this.el);
        })
        .catch(() => {});
    }

    return { toc, frontMatter, ms: performance.now() - started };
  }

  /* --- scroll sync ------------------------------------------------------- */

  /** Sorted [line, offsetTop] pairs for every block that carries data-line. */
  buildLineIndex() {
    const nodes = this.el.querySelectorAll('[data-line]');
    const index = [];
    let last = -1;
    for (const node of nodes) {
      const line = Number(node.getAttribute('data-line'));
      if (!Number.isFinite(line) || line <= last) continue;
      index.push([line, node.offsetTop, node]);
      last = line;
    }
    this.lineIndex = index;
  }

  /** Pixel offset for a source line, interpolating between known anchors. */
  offsetForLine(line) {
    const idx = this.lineIndex;
    if (!idx.length) return 0;
    if (line <= idx[0][0]) return 0;

    let lo = 0, hi = idx.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (idx[mid][0] <= line) lo = mid; else hi = mid - 1;
    }
    const [l0, y0] = idx[lo];
    if (lo === idx.length - 1) return y0;
    const [l1, y1] = idx[lo + 1];
    const span = l1 - l0;
    return span <= 0 ? y0 : y0 + ((line - l0) / span) * (y1 - y0);
  }

  /** Inverse of offsetForLine: which source line sits at this scroll offset. */
  lineForOffset(offset) {
    const idx = this.lineIndex;
    if (!idx.length) return 0;

    let lo = 0, hi = idx.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (idx[mid][1] <= offset) lo = mid; else hi = mid - 1;
    }
    const [l0, y0] = idx[lo];
    if (lo === idx.length - 1) return l0;
    const [l1, y1] = idx[lo + 1];
    const span = y1 - y0;
    return span <= 0 ? l0 : l0 + ((offset - y0) / span) * (l1 - l0);
  }
}
