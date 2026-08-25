/* Mermaid is ~3 MB, so it is loaded only when a document actually contains a
   diagram. The import is dynamic; esbuild emits it as a separate chunk. */

let mermaidPromise = null;
let currentTheme = null;
let counter = 0;

function themeVariables(dark) {
  /* Diagram colours drawn from the design tokens so charts sit inside the
     document rather than looking like a pasted-in third-party widget. */
  return dark
    ? { background: '#1c1b19', primaryColor: '#252320', primaryTextColor: '#faf9f5',
        primaryBorderColor: '#4a463f', lineColor: '#857f76', secondaryColor: '#2f2c28',
        tertiaryColor: '#232120', textColor: '#d4d0c8', mainBkg: '#252320',
        nodeBorder: '#5a5449', clusterBkg: '#1f1e1b', clusterBorder: '#3d3a34',
        titleColor: '#faf9f5', edgeLabelBackground: '#1c1b19',
        actorBkg: '#252320', actorBorder: '#5a5449', actorTextColor: '#faf9f5',
        signalColor: '#a09d96', signalTextColor: '#d4d0c8',
        labelBoxBkgColor: '#252320', labelTextColor: '#faf9f5',
        pie1: '#cc785c', pie2: '#5db8a6', pie3: '#e8a55a', pie4: '#8fb3d1',
        pie5: '#a9583e', pie6: '#6c6a64' }
    : { background: '#f5f0e8', primaryColor: '#efe9de', primaryTextColor: '#141413',
        primaryBorderColor: '#cfc6b6', lineColor: '#8e8b82', secondaryColor: '#e8e0d2',
        tertiaryColor: '#faf9f5', textColor: '#3d3d3a', mainBkg: '#efe9de',
        nodeBorder: '#cfc6b6', clusterBkg: '#faf9f5', clusterBorder: '#e6dfd8',
        titleColor: '#141413', edgeLabelBackground: '#f5f0e8',
        actorBkg: '#efe9de', actorBorder: '#cfc6b6', actorTextColor: '#141413',
        signalColor: '#6c6a64', signalTextColor: '#3d3d3a',
        labelBoxBkgColor: '#efe9de', labelTextColor: '#141413',
        pie1: '#cc785c', pie2: '#5db8a6', pie3: '#e8a55a', pie4: '#8fb3d1',
        pie5: '#a9583e', pie6: '#8e8b82' };
}

async function getMermaid(dark) {
  if (!mermaidPromise) {
    mermaidPromise = import('mermaid').then((m) => m.default ?? m);
  }
  const mermaid = await mermaidPromise;
  if (currentTheme !== dark) {
    currentTheme = dark;
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'strict',
      theme: 'base',
      themeVariables: themeVariables(dark),
      fontFamily: 'Inter, -apple-system, sans-serif',
      flowchart: { curve: 'basis', htmlLabels: true },
    });
  }
  return mermaid;
}

/** Renders every pending .mermaid-block inside `root`. */
export async function renderMermaid(root, { dark = false } = {}) {
  const blocks = [...root.querySelectorAll('.mermaid-block[data-state="pending"]')];
  if (!blocks.length) return 0;

  let mermaid;
  try {
    mermaid = await getMermaid(dark);
  } catch (err) {
    for (const b of blocks) fail(b, `Could not load Mermaid: ${err.message}`);
    return 0;
  }

  let done = 0;
  for (const block of blocks) {
    const source = block.querySelector('.mermaid-source')?.textContent ?? '';
    const target = block.querySelector('.mermaid-target');
    if (!target) continue;
    try {
      const { svg } = await mermaid.render(`mmd-${++counter}`, source);
      target.innerHTML = svg;
      block.dataset.state = 'done';
      done++;
    } catch (err) {
      fail(block, String(err?.message ?? err));
    }
  }
  return done;
}

function fail(block, message) {
  const target = block.querySelector('.mermaid-target');
  block.dataset.state = 'error';
  if (target) {
    target.innerHTML = '';
    const pre = document.createElement('pre');
    pre.className = 'mermaid-error';
    pre.textContent = `Mermaid: ${message}`;
    target.appendChild(pre);
  }
}

/** Forces a re-render, e.g. after a light/dark switch. */
export function resetMermaid(root) {
  for (const b of root.querySelectorAll('.mermaid-block')) {
    if (b.dataset.state === 'done') b.dataset.state = 'pending';
  }
}
