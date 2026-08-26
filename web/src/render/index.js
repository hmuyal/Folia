import MarkdownIt      from 'markdown-it';
import markPlugin      from 'markdown-it-mark';
import subPlugin       from 'markdown-it-sub';
import supPlugin       from 'markdown-it-sup';
import insPlugin       from 'markdown-it-ins';
import footnotePlugin  from 'markdown-it-footnote';
import deflistPlugin   from 'markdown-it-deflist';
import abbrPlugin      from 'markdown-it-abbr';
import anchorPlugin    from 'markdown-it-anchor';
import attrsPlugin     from 'markdown-it-attrs';
import containerPlugin from 'markdown-it-container';
import taskListPlugin  from 'markdown-it-task-lists';
import katexPlugin     from '@vscode/markdown-it-katex';
import { full as emojiPlugin } from 'markdown-it-emoji';

import { DEFAULT_OPTIONS }               from './options.js';
import { alertsPlugin, ADMONITION_ICONS } from './alerts.js';
import { codeWindowPlugin, highlightCode, wrapLines, escapeHTML } from './codeWindow.js';
import { imagesPlugin }                  from './images.js';
import { lineMapPlugin }                 from './lineMap.js';
import { extractFrontMatter, renderFrontMatter } from './frontmatter.js';

/* GitHub's heading-slug algorithm: lowercase, drop punctuation, spaces to dashes. */
export function slugify(text) {
  return String(text)
    .trim()
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\p{M}\s_-]/gu, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '') || 'section';
}

/* [[Page]] and [[Page|Label]] */
function wikiLinksPlugin(md) {
  md.inline.ruler.before('link', 'wikilink', (state, silent) => {
    const { src, pos } = state;
    if (src.charCodeAt(pos) !== 0x5B || src.charCodeAt(pos + 1) !== 0x5B) return false;
    const end = src.indexOf(']]', pos + 2);
    if (end === -1) return false;

    const inner = src.slice(pos + 2, end);
    if (inner.includes('[') || inner.includes('\n')) return false;

    if (!silent) {
      const [target, label] = inner.split('|');
      const open = state.push('link_open', 'a', 1);
      open.attrSet('href', target.trim());
      open.attrSet('data-wikilink', '1');
      open.attrSet('data-internal', '1');
      const text = state.push('text', '', 0);
      text.content = (label ?? target).trim();
      state.push('link_close', 'a', -1);
    }
    state.pos = end + 2;
    return true;
  });
}

/* Collects the outline while rendering. */
function tocPlugin(md) {
  md.core.ruler.push('collect_toc', (state) => {
    const toc = [];
    const tokens = state.tokens;
    for (let i = 0; i < tokens.length; i++) {
      const t = tokens[i];
      if (t.type !== 'heading_open') continue;
      const inline = tokens[i + 1];
      toc.push({
        level: Number(t.tag.slice(1)),
        text:  inline && inline.type === 'inline' ? inline.content.replace(/[*_`~]/g, '') : '',
        id:    t.attrGet('id') || '',
        line:  t.map ? t.map[0] : 0,
      });
    }
    state.env.toc = toc;
    return true;
  });
}

/* Tables scroll rather than wrap, and break out of the prose measure. */
function tableWrapPlugin(md) {
  md.renderer.rules.table_open = (tokens, idx) => {
    const line = tokens[idx].map ? ` data-line="${tokens[idx].map[0]}"` : '';
    return `<div class="table-wrap breakout"${line}><table>`;
  };
  md.renderer.rules.table_close = () => '</table></div>\n';
}

function buildInstance(opts) {
  const md = new MarkdownIt({
    html:        opts.allowHTML,
    xhtmlOut:    false,
    breaks:      opts.hardBreak,
    linkify:     opts.autolink,
    typographer: opts.smartQuotes,
    quotes:      '“”‘’',
    highlight:   null, // fence rule is fully replaced below
  });

  if (!opts.table)         md.disable('table');
  if (!opts.strikethrough) md.disable('strikethrough');
  if (opts.noSoftBreak && !opts.hardBreak) {
    md.renderer.rules.softbreak = () => ' ';
  }

  if (opts.highlight)   md.use(markPlugin);
  if (opts.subscript)   md.use(subPlugin);
  if (opts.superscript) md.use(supPlugin);
  if (opts.inserted)    md.use(insPlugin);
  if (opts.deflist)     md.use(deflistPlugin);
  if (opts.abbr)        md.use(abbrPlugin);
  if (opts.attrs)       md.use(attrsPlugin, { allowedAttributes: ['id', 'class', 'align', 'width', 'height', 'title'] });
  if (opts.emoji)       md.use(emojiPlugin);
  if (opts.footnotes)   md.use(footnotePlugin);
  if (opts.taskList)    md.use(taskListPlugin, { enabled: true, label: false });
  if (opts.wikiLinks)   md.use(wikiLinksPlugin);
  if (opts.alerts)      md.use(alertsPlugin);

  if (opts.containers) {
    for (const kind of ['note', 'tip', 'important', 'warning', 'caution', 'info']) {
      md.use(containerPlugin, kind, {
        render(tokens, idx) {
          if (tokens[idx].nesting !== 1) return '</div></div>\n';
          const k = kind === 'info' ? 'note' : kind;
          const label = k.charAt(0).toUpperCase() + k.slice(1);
          const raw = tokens[idx].info.trim().slice(kind.length).trim();
          const line = tokens[idx].map ? ` data-line="${tokens[idx].map[0]}"` : '';
          return `<div class="admonition admonition--${k}"${line}>` +
                 `<div class="admonition__title">${ADMONITION_ICONS[k] || ''}` +
                 `${escapeHTML(raw || label)}</div><div class="admonition__body">`;
        },
      });
    }
  }

  if (opts.math) {
    md.use(katexPlugin.default ?? katexPlugin, {
      throwOnError: false,
      errorColor: '#c64545',
      output: 'html',
    });
  }

  if (opts.headsAnchors) {
    md.use(anchorPlugin, {
      slugify,
      tabIndex: false,
      permalink: anchorPlugin.permalink.linkInsideHeader({
        symbol: '#',
        class: 'heading-anchor',
        placement: 'before',
        ariaHidden: true,
      }),
    });
  }

  codeWindowPlugin(md, () => opts);
  imagesPlugin(md, () => opts);
  tableWrapPlugin(md);
  tocPlugin(md);
  lineMapPlugin(md);

  return md;
}

let cached = { key: null, md: null };

function instanceFor(opts) {
  const key = JSON.stringify(opts);
  if (cached.key !== key) cached = { key, md: buildInstance(opts) };
  return cached.md;
}

/* Whole document as syntax-highlighted source — a "render as source code"
   mode. */
function renderAsSource(src) {
  const { html } = highlightCode(src, 'markdown', true);
  return {
    html: `<figure class="code-window breakout" data-numbers="1" data-wrap="0" data-lang="markdown">` +
          `<figcaption class="code-window__bar"><span class="code-window__lang">Markdown source</span>` +
          `<button class="code-window__copy" type="button" data-copy>Copy</button></figcaption>` +
          `<div class="code-window__body"><pre><code class="hljs language-markdown">${wrapLines(html)}</code></pre></div>` +
          `</figure>`,
    toc: [],
    frontMatter: null,
  };
}

/**
 * Render Markdown to the document HTML.
 * @param {string} src
 * @param {object} userOptions  partial overrides of DEFAULT_OPTIONS
 * @returns {{html: string, toc: Array, frontMatter: object|null}}
 */
export function render(src, userOptions = {}) {
  const opts = { ...DEFAULT_OPTIONS, ...userOptions };

  if (typeof src !== 'string') src = String(src ?? '');
  if (opts.renderAsSource) return renderAsSource(src);

  if (src.trim() === '') {
    return { html: '<p class="md-empty">This document is empty.</p>', toc: [], frontMatter: null };
  }

  const fm = opts.yamlHeader
    ? extractFrontMatter(src)
    : { body: src, raw: null, data: null, kind: null, error: null };

  const md  = instanceFor(opts);
  const env = {};
  let body;
  try {
    body = md.render(fm.body, env);
  } catch (err) {
    body = `<div class="admonition admonition--caution"><div class="admonition__title">Render error</div>` +
           `<div class="admonition__body"><p>${escapeHTML(err.message)}</p></div></div>`;
  }

  return {
    html: renderFrontMatter(fm) + body,
    toc: env.toc || [],
    frontMatter: fm.data,
  };
}

export { DEFAULT_OPTIONS };
