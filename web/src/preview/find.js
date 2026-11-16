/* Find in the rendered document.

   Everywhere else ⌘F opens CodeMirror's search panel, but reader mode has no
   editor pane to show it in. This is the reader's own find: a small bar over
   the preview that highlights matches without touching the rendered DOM (CSS
   Custom Highlight API), so export, copy and scroll sync see the same document
   they always did. */

const ALL = 'folia-find';
const CURRENT = 'folia-find-current';

/* Not document text: hidden MathML twins of KaTeX output, and code-window
   chrome (language label, Copy button). */
const SKIP = 'script, style, .katex-mathml, .code-window__bar';

/* Text in different blocks must not read as one run, or "…end" + "Start…"
   would match "dS". */
const BLOCKS = 'p, li, h1, h2, h3, h4, h5, h6, pre, td, th, dt, dd, blockquote, figcaption, summary, div';

/* A one-letter query in a long document matches tens of thousands of times;
   nobody steps through those, and painting them stalls typing. */
const LIMIT = 5000;

const canHighlight = typeof Highlight !== 'undefined' && Boolean(globalThis.CSS?.highlights);

const CHEVRON = (d) =>
  `<svg viewBox="0 0 12 12" width="12" height="12" aria-hidden="true"><path d="${d}" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>`;

export class PreviewFind {
  constructor(root, { content, scroller }) {
    this.content = content;
    this.scroller = scroller;
    this.matches = [];
    this.current = -1;
    this.capped = false;
    this.refreshFrame = null;

    this.bar = document.createElement('div');
    this.bar.className = 'findbar';
    this.bar.hidden = true;
    this.bar.setAttribute('role', 'search');
    this.bar.innerHTML =
      `<input class="findbar__input" type="text" placeholder="Find in document" ` +
        `aria-label="Find in document" spellcheck="false" autocomplete="off" autocapitalize="off">` +
      `<span class="findbar__count" aria-live="polite"></span>` +
      `<button class="findbar__btn" type="button" data-find="prev" aria-label="Previous match" title="Previous (⇧⌘G)">${CHEVRON('M2.5 7.5 6 4l3.5 3.5')}</button>` +
      `<button class="findbar__btn" type="button" data-find="next" aria-label="Next match" title="Next (⌘G)">${CHEVRON('M2.5 4.5 6 8l3.5-3.5')}</button>` +
      `<button class="findbar__btn" type="button" data-find="close" aria-label="Close find" title="Close (esc)">${CHEVRON('M3 3l6 6M9 3l-6 6')}</button>`;
    root.appendChild(this.bar);

    this.input = this.bar.querySelector('.findbar__input');
    this.count = this.bar.querySelector('.findbar__count');

    this.input.addEventListener('input', () => this.search({ reveal: true }));
    this.input.addEventListener('keydown', (event) => {
      if (event.key !== 'Enter') return;
      event.preventDefault();
      this.step(event.shiftKey ? -1 : 1);
    });

    // Buttons act without taking focus, so typing carries on where it was.
    this.bar.addEventListener('mousedown', (event) => {
      if (event.target.closest('.findbar__btn')) event.preventDefault();
    });
    this.bar.addEventListener('click', (event) => {
      const action = event.target.closest('[data-find]')?.dataset.find;
      if (action === 'prev') this.step(-1);
      if (action === 'next') this.step(1);
      if (action === 'close') this.close();
    });

    window.addEventListener('keydown', (event) => {
      if (!this.isOpen) return;
      if (event.key === 'Escape') {
        event.preventDefault();
        this.close();
      } else if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'g') {
        event.preventDefault();
        this.step(event.shiftKey ? -1 : 1);
      }
    });

    // The document re-renders under an open bar (external file change, a tab
    // switch, Mermaid finishing). Ranges into the old nodes are dead, so
    // search again — quietly, without moving the reader.
    this.observer = new MutationObserver(() => {
      if (this.refreshFrame) return;
      this.refreshFrame = requestAnimationFrame(() => {
        this.refreshFrame = null;
        if (this.isOpen) this.search({ reveal: false });
      });
    });
  }

  get isOpen() { return !this.bar.hidden; }

  open() {
    if (!this.isOpen) {
      this.bar.hidden = false;
      this.observer.observe(this.content, { childList: true, subtree: true, characterData: true });
    }
    this.input.focus();
    this.input.select();
    this.search({ reveal: true });
  }

  close() {
    if (!this.isOpen) return;
    this.bar.hidden = true;
    this.observer.disconnect();
    this.input.blur();
    this.matches = [];
    this.current = -1;
    this.paint();
  }

  /* --- searching --------------------------------------------------------- */

  search({ reveal }) {
    const previous = this.current;
    this.matches = [];
    this.current = -1;
    this.capped = false;

    const query = this.input.value;
    if (query.trim()) {
      const { text, nodes, starts } = this.index();
      // A space in the query matches any run of whitespace: a soft-wrapped
      // source line renders as "foo\nbar" but reads as "foo bar".
      const pattern = query
        .replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
        .replace(/\s+/g, '\\s+');
      for (const hit of text.matchAll(new RegExp(pattern, 'giu'))) {
        if (!hit[0].length) continue;
        const range = this.rangeFor(nodes, starts, hit.index, hit.index + hit[0].length);
        if (range) this.matches.push(range);
        if (this.matches.length >= LIMIT) { this.capped = true; break; }
      }
    }

    if (this.matches.length) {
      this.current = reveal
        ? this.firstFromViewport()
        : Math.min(Math.max(previous, 0), this.matches.length - 1);
    }
    this.paint();
    if (reveal) this.reveal();
  }

  /** One string of everything readable, plus where each text node sits in it. */
  index() {
    const nodes = [];
    const starts = [];
    let text = '';
    let lastBlock = null;

    const walker = document.createTreeWalker(this.content, NodeFilter.SHOW_TEXT, {
      acceptNode: (node) => (node.parentElement?.closest(SKIP)
        ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT),
    });
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const block = node.parentElement.closest(BLOCKS);
      if (block !== lastBlock && text) text += '\n';
      lastBlock = block;
      nodes.push(node);
      starts.push(text.length);
      text += node.data;
    }
    return { text, nodes, starts };
  }

  rangeFor(nodes, starts, from, to) {
    const locate = (offset, isEnd) => {
      // Last node starting at or before the offset; an end offset sitting
      // exactly on a node's start belongs to the node before it.
      let lo = 0, hi = nodes.length - 1;
      while (lo < hi) {
        const mid = (lo + hi + 1) >> 1;
        const before = isEnd ? starts[mid] < offset : starts[mid] <= offset;
        if (before) lo = mid; else hi = mid - 1;
      }
      return [nodes[lo], Math.min(offset - starts[lo], nodes[lo].length)];
    };
    const [startContainer, startOffset] = locate(from, false);
    const [endContainer, endOffset] = locate(to, true);
    if (startOffset < 0 || endOffset < 0) return null;
    return new StaticRange({ startContainer, startOffset, endContainer, endOffset });
  }

  /* --- moving between matches -------------------------------------------- */

  step(delta) {
    if (!this.matches.length) return;
    this.current = (this.current + delta + this.matches.length) % this.matches.length;
    this.paint();
    this.reveal();
  }

  /** The first match at or below the top of what is on screen — typing a
   *  query should not throw the reader back to the start of the document. */
  firstFromViewport() {
    const top = this.scroller.getBoundingClientRect().top;
    let lo = 0, hi = this.matches.length - 1;
    if (this.live(this.matches[hi]).getBoundingClientRect().bottom < top) return 0;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (this.live(this.matches[mid]).getBoundingClientRect().bottom < top) lo = mid + 1;
      else hi = mid;
    }
    return lo;
  }

  reveal() {
    const match = this.matches[this.current];
    if (!match) return;

    // A match inside a collapsed <details> has no box to scroll to.
    let closed = match.startContainer.parentElement?.closest('details:not([open])');
    while (closed) {
      closed.open = true;
      closed = closed.parentElement?.closest('details:not([open])');
    }

    const range = this.live(match);

    // Wide code blocks and tables scroll sideways on their own.
    for (let el = match.startContainer.parentElement; el && el !== this.content; el = el.parentElement) {
      if (el.scrollWidth <= el.clientWidth + 1) continue;
      const box = el.getBoundingClientRect();
      const rect = range.getBoundingClientRect();
      if (rect.left < box.left || rect.right > box.right) {
        el.scrollLeft += rect.left - box.left - box.width / 3;
      }
    }

    const pane = this.scroller.getBoundingClientRect();
    const rect = range.getBoundingClientRect();
    const margin = 64;      // also keeps the match clear of the bar itself
    if (rect.top < pane.top + margin || rect.bottom > pane.bottom - margin) {
      this.scroller.scrollTop += rect.top - pane.top - pane.height / 3;
    }
  }

  live(match) {
    const range = document.createRange();
    range.setStart(match.startContainer, match.startOffset);
    range.setEnd(match.endContainer, match.endOffset);
    return range;
  }

  /* --- painting ---------------------------------------------------------- */

  paint() {
    const total = this.matches.length;
    const hasQuery = Boolean(this.input.value.trim());
    this.count.textContent = !hasQuery ? ''
      : total ? `${this.current + 1} of ${total}${this.capped ? '+' : ''}`
      : 'No results';
    this.bar.classList.toggle('findbar--empty', hasQuery && !total);

    if (!canHighlight) return;
    if (!total) {
      CSS.highlights.delete(ALL);
      CSS.highlights.delete(CURRENT);
      return;
    }
    CSS.highlights.set(ALL, new Highlight(...this.matches));
    const current = new Highlight(this.matches[this.current]);
    current.priority = 1;
    CSS.highlights.set(CURRENT, current);
  }
}
