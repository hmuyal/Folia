/* Two panes and a draggable divider. View mode decides which panes exist. */

export class Layout {
  constructor(root, { onRatioChange } = {}) {
    this.root = root;
    this.onRatioChange = onRatioChange ?? (() => {});
    this.ratio = 0.5;
    this.mode = 'split';

    root.classList.add('app');
    root.innerHTML = `
      <div class="pane pane--editor"><div class="editor-host"></div></div>
      <div class="splitter" role="separator" aria-orientation="vertical" tabindex="0"></div>
      <div class="pane pane--preview"><article class="md-doc"></article></div>
    `;

    this.editorPane  = root.querySelector('.pane--editor');
    this.previewPane = root.querySelector('.pane--preview');
    this.editorHost  = root.querySelector('.editor-host');
    this.previewHost = root.querySelector('.md-doc');
    this.splitter    = root.querySelector('.splitter');

    this.bindSplitter();
    this.setMode('split');
    this.setRatio(0.5);
  }

  setMode(mode) {
    this.mode = mode;
    this.root.dataset.view = mode;
    // Widths are only meaningful in split mode; the others go full-bleed.
    if (mode === 'split') this.applyRatio();
    else {
      this.editorPane.style.flex = '';
      this.previewPane.style.flex = '';
    }
  }

  setRatio(ratio) {
    this.ratio = Math.min(0.85, Math.max(0.15, ratio));
    if (this.mode === 'split') this.applyRatio();
  }

  applyRatio() {
    this.editorPane.style.flex  = `${this.ratio} 1 0`;
    this.previewPane.style.flex = `${1 - this.ratio} 1 0`;
  }

  bindSplitter() {
    let dragging = false;

    const move = (event) => {
      if (!dragging) return;
      const rect = this.root.getBoundingClientRect();
      this.setRatio((event.clientX - rect.left) / rect.width);
    };

    const stop = () => {
      if (!dragging) return;
      dragging = false;
      document.body.classList.remove('is-dragging');
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', stop);
      this.onRatioChange(this.ratio);
    };

    this.splitter.addEventListener('pointerdown', (event) => {
      if (this.mode !== 'split') return;
      dragging = true;
      document.body.classList.add('is-dragging');
      event.preventDefault();
      window.addEventListener('pointermove', move);
      window.addEventListener('pointerup', stop);
    });

    // Double-click resets to an even split.
    this.splitter.addEventListener('dblclick', () => {
      this.setRatio(0.5);
      this.onRatioChange(this.ratio);
    });

    // Keyboard-accessible: arrows nudge the divider.
    this.splitter.addEventListener('keydown', (event) => {
      const step = event.shiftKey ? 0.1 : 0.02;
      if (event.key === 'ArrowLeft')  { this.setRatio(this.ratio - step); this.onRatioChange(this.ratio); }
      if (event.key === 'ArrowRight') { this.setRatio(this.ratio + step); this.onRatioChange(this.ratio); }
    });
  }
}
