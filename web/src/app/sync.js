/**
 * Bidirectional scroll sync.
 *
 * Both directions write to the other pane's scroll position, which would
 * ping-pong forever without a lock. Whichever pane the user last touched owns
 * the scroll for a short window; the other one follows and its own scroll
 * events are ignored.
 */
export class ScrollSync {
  constructor({ editor, preview, previewScroller }) {
    this.editor = editor;
    this.preview = preview;
    this.previewScroller = previewScroller;
    this.enabled = true;
    this.owner = null;          // 'editor' | 'preview' | null
    this.releaseTimer = null;
    this.frame = null;

    this.previewScroller.addEventListener('scroll', () => this.fromPreview(), { passive: true });
  }

  setEnabled(on) { this.enabled = on; }

  claim(owner) {
    this.owner = owner;
    clearTimeout(this.releaseTimer);
    this.releaseTimer = setTimeout(() => { this.owner = null; }, 220);
  }

  /** Called by the editor's scroll handler. */
  fromEditor(topLine) {
    if (!this.enabled || this.owner === 'preview') return;
    this.claim('editor');
    this.schedule(() => {
      const offset = this.preview.offsetForLine(topLine);
      this.previewScroller.scrollTop = offset;
    });
  }

  fromPreview() {
    if (!this.enabled || this.owner === 'editor') return;
    this.claim('preview');
    this.schedule(() => {
      const line = this.preview.lineForOffset(this.previewScroller.scrollTop);
      this.editor.scrollLineToTop(line);
    });
  }

  /** Coalesces to one write per frame; scroll events fire far faster. */
  schedule(fn) {
    if (this.frame) return;
    this.frame = requestAnimationFrame(() => {
      this.frame = null;
      fn();
    });
  }

  /** After a re-render the line index moved; realign without claiming. */
  realign(topLine) {
    if (!this.enabled) return;
    const offset = this.preview.offsetForLine(topLine);
    this.previewScroller.scrollTop = offset;
  }
}
