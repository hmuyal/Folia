/* GitHub alerts:  > [!NOTE] / [!TIP] / [!IMPORTANT] / [!WARNING] / [!CAUTION]
   Rewrites the blockquote token pair into an admonition. Runs before the
   inline rule so token.content can be edited as plain text. */

const ICONS = {
  note:      '<svg viewBox="0 0 16 16"><path d="M8 0a8 8 0 110 16A8 8 0 018 0zm.75 4.25a.75.75 0 10-1.5 0 .75.75 0 001.5 0zM7.25 7v4.5a.75.75 0 001.5 0V7a.75.75 0 00-1.5 0z"/></svg>',
  tip:       '<svg viewBox="0 0 16 16"><path d="M8 0a5.5 5.5 0 00-3.3 9.9c.4.3.6.7.7 1.1l.2 1a.75.75 0 00.74.6h3.32a.75.75 0 00.74-.6l.2-1c.1-.4.3-.8.7-1.1A5.5 5.5 0 008 0zM6.3 14.25a.75.75 0 01.75-.75h1.9a.75.75 0 010 1.5h-1.9a.75.75 0 01-.75-.75z"/></svg>',
  important: '<svg viewBox="0 0 16 16"><path d="M0 2.75A1.75 1.75 0 011.75 1h12.5A1.75 1.75 0 0116 2.75v8.5A1.75 1.75 0 0114.25 13H8.06l-2.9 2.9A.75.75 0 014 15.37V13H1.75A1.75 1.75 0 010 11.25zM8.75 3.75a.75.75 0 00-1.5 0v3.5a.75.75 0 001.5 0zM8 9.5A.88.88 0 108 11a.88.88 0 000-1.5z"/></svg>',
  warning:   '<svg viewBox="0 0 16 16"><path d="M6.46 1.14a1.75 1.75 0 013.08 0l5.7 10.36A1.75 1.75 0 0113.71 14H2.29a1.75 1.75 0 01-1.53-2.5zM8.75 5.25a.75.75 0 00-1.5 0v3a.75.75 0 001.5 0zM8 10.5a.88.88 0 100 1.75.88.88 0 000-1.75z"/></svg>',
  caution:   '<svg viewBox="0 0 16 16"><path d="M4.47.22A.75.75 0 015 0h6a.75.75 0 01.53.22l4.25 4.25c.14.14.22.33.22.53v6a.75.75 0 01-.22.53l-4.25 4.25a.75.75 0 01-.53.22H5a.75.75 0 01-.53-.22L.22 11.53A.75.75 0 010 11V5a.75.75 0 01.22-.53zM8.75 4.75a.75.75 0 00-1.5 0v3.5a.75.75 0 001.5 0zM8 10.5a.88.88 0 100 1.75.88.88 0 000-1.75z"/></svg>',
};

const RE = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*(?:\r?\n|$)/i;

export function alertsPlugin(md) {
  md.core.ruler.before('inline', 'github_alerts', (state) => {
    const tokens = state.tokens;

    for (let i = 0; i < tokens.length; i++) {
      if (tokens[i].type !== 'blockquote_open') continue;

      const pOpen  = tokens[i + 1];
      const inline = tokens[i + 2];
      if (!pOpen || pOpen.type !== 'paragraph_open') continue;
      if (!inline || inline.type !== 'inline') continue;

      const m = RE.exec(inline.content);
      if (!m) continue;

      const kind = m[1].toLowerCase();

      // Find the matching close, honouring nesting.
      let depth = 0, close = -1;
      for (let j = i; j < tokens.length; j++) {
        if (tokens[j].type === 'blockquote_open')  depth++;
        if (tokens[j].type === 'blockquote_close') { depth--; if (depth === 0) { close = j; break; } }
      }
      if (close === -1) continue;

      inline.content = inline.content.slice(m[0].length);

      tokens[i].type = 'admonition_open';
      tokens[i].tag  = 'div';
      tokens[i].meta = { kind };
      tokens[close].type = 'admonition_close';
      tokens[close].tag  = 'div';

      // The marker was the whole first paragraph -> drop the empty paragraph.
      if (inline.content.trim() === '') {
        tokens.splice(i + 1, 3);
        close -= 3;
      }
    }
    return true;
  });

  md.renderer.rules.admonition_open = (tokens, idx) => {
    const kind = tokens[idx].meta.kind;
    const label = kind.charAt(0).toUpperCase() + kind.slice(1);
    const line = tokens[idx].map ? ` data-line="${tokens[idx].map[0]}"` : '';
    return `<div class="admonition admonition--${kind}"${line}>` +
           `<div class="admonition__title">${ICONS[kind] || ''}${label}</div>` +
           `<div class="admonition__body">`;
  };
  md.renderer.rules.admonition_close = () => `</div></div>\n`;
}

export const ADMONITION_ICONS = ICONS;
