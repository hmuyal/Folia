import { resolveAssetURL } from '../render/images.js';

/* Everything that needs a live DOM: measuring, lazy assets, interaction. */

/** Images inside raw HTML never passed through the renderer's image rule. */
export function resolveRawImages(root, opts) {
  for (const img of root.querySelectorAll('img')) {
    const src = img.getAttribute('src') || '';
    if (!src || src.startsWith('folia://') || src.startsWith('data:')) continue;
    img.setAttribute('data-src-original', src);
    img.setAttribute('src', resolveAssetURL(src, opts));
  }
}

/** Replaces images that fail to load with a legible marker. */
export function markBrokenImages(root) {
  for (const img of root.querySelectorAll('img')) {
    if (img.dataset.errorBound) continue;
    img.dataset.errorBound = '1';
    img.addEventListener('error', () => {
      if (img.dataset.replaced) return;
      img.dataset.replaced = '1';
      const span = document.createElement('span');
      span.className = 'md-image-error';
      const original = img.getAttribute('data-src-original') || img.getAttribute('src') || '';
      const blocked = original.startsWith('folia://blocked') || img.src.includes('folia://blocked');
      span.textContent = blocked
        ? `remote image blocked — ${decodeURIComponent(original.replace('folia://blocked/', ''))}`
        : `image not found — ${original}`;
      img.replaceWith(span);
    }, { once: true });
  }
}

/**
 * Breakout is conditional: an element only leaves the prose measure when its
 * content genuinely overflows it. Otherwise a narrow table would sit
 * misaligned from the paragraph that introduces it.
 *
 * Measuring has to happen at the NARROW width — asking an already-widened
 * element whether it overflows always answers no. So: collapse everything to
 * the prose measure, take one batched read, then promote only what overflowed.
 */
export function applyConditionalBreakout(root) {
  const candidates = [...root.querySelectorAll('.code-window, .table-wrap, .mermaid-block')];
  if (!candidates.length) return;

  for (const el of candidates) el.classList.remove('breakout');

  const overflowing = candidates.filter((el) => {
    const scroller = el.classList.contains('code-window')
      ? el.querySelector('.code-window__body')
      : el;
    if (!scroller) return false;
    /* 2px of slack absorbs sub-pixel rounding. */
    return scroller.scrollWidth > scroller.clientWidth + 2;
  });

  for (const el of overflowing) el.classList.add('breakout');
}

/** Copy-to-clipboard on code windows. Delegated, so it survives re-render. */
export function bindCopyButtons(root) {
  if (root.dataset.copyBound) return;
  root.dataset.copyBound = '1';
  root.addEventListener('click', (ev) => {
    const btn = ev.target.closest('[data-copy]');
    if (!btn) return;
    const fig = btn.closest('.code-window');
    const code = fig?.querySelector('code');
    if (!code) return;
    const text = [...code.querySelectorAll('.cl')]
      .map((l) => l.textContent.replace(/​/g, ''))
      .join('\n');
    navigator.clipboard.writeText(text).then(
      () => flash(btn, 'Copied'),
      () => flash(btn, 'Failed'),
    );
  });
}

function flash(btn, label) {
  const original = btn.textContent;
  btn.textContent = label;
  btn.dataset.copied = '1';
  setTimeout(() => { btn.textContent = original; delete btn.dataset.copied; }, 1400);
}

/**
 * Link routing. Nothing navigates the WebView itself:
 *  - in-page #anchors scroll locally
 *  - external links are handed to the host, which opens the default browser
 *  - relative document links ask the host to open that file
 */
export function bindLinks(root, host) {
  if (root.dataset.linkBound) return;
  root.dataset.linkBound = '1';
  root.addEventListener('click', (ev) => {
    const a = ev.target.closest('a[href]');
    if (!a || !root.contains(a)) return;
    const href = a.getAttribute('href') || '';

    if (a.dataset.blocked) { ev.preventDefault(); return; }

    if (href.startsWith('#')) {
      ev.preventDefault();
      const target = root.querySelector(`[id="${CSS.escape(href.slice(1))}"]`);
      if (target) {
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        target.classList.remove('sync-flash');
        void target.offsetWidth;
        target.classList.add('sync-flash');
      }
      return;
    }

    ev.preventDefault();
    if (a.dataset.external) host?.openExternal?.(href);
    else host?.openRelative?.(href);
  });
}

/** Task-list checkboxes write back into the source document. */
export function bindTaskLists(root, host) {
  if (root.dataset.taskBound) return;
  root.dataset.taskBound = '1';
  root.addEventListener('change', (ev) => {
    const box = ev.target.closest('.task-list-item-checkbox');
    if (!box) return;
    const li = box.closest('li');
    const block = box.closest('[data-line]') || li?.closest('[data-line]');
    if (!block) return;
    /* Index of this checkbox among all checkboxes, so the host can find the
       matching "- [ ]" in the source without needing exact line maps. */
    const all = [...root.querySelectorAll('.task-list-item-checkbox')];
    host?.toggleTask?.(all.indexOf(box), box.checked);
  });
}
