import yaml from 'js-yaml';

/* Extracts YAML/TOML front matter.
   The matched region is replaced by BLANK LINES rather than removed, so every
   downstream line number still matches the editor. Scroll sync depends on it. */

const FENCE = /^(---|\+\+\+)[ \t]*\r?\n([\s\S]*?)\r?\n\1[ \t]*(?:\r?\n|$)/;

export function extractFrontMatter(src) {
  if (!src.startsWith('---') && !src.startsWith('+++')) {
    return { body: src, raw: null, data: null, kind: null, error: null };
  }
  const m = FENCE.exec(src);
  if (!m) return { body: src, raw: null, data: null, kind: null, error: null };

  const raw = m[2];
  const consumed = m[0];
  const blanks = '\n'.repeat((consumed.match(/\n/g) || []).length);
  const body = blanks + src.slice(consumed.length);

  let data = null, error = null;
  if (m[1] === '---') {
    try {
      data = yaml.load(raw, { schema: yaml.JSON_SCHEMA });
    } catch (e) {
      error = e.message;
    }
  }
  return { body, raw, data, kind: m[1] === '---' ? 'yaml' : 'toml', error };
}

function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}

function scalar(v) {
  if (v === null || v === undefined) return '<span style="opacity:.5">—</span>';
  if (Array.isArray(v)) {
    return v.map((x) => `<span class="fm-chip">${esc(typeof x === 'object' ? JSON.stringify(x) : x)}</span>`).join(' ');
  }
  if (typeof v === 'object') {
    return `<code>${esc(JSON.stringify(v))}</code>`;
  }
  if (typeof v === 'boolean') return v ? '✓ true' : '✗ false';
  return esc(v);
}

/* Renders front matter as the metadata card QLMarkdown produces. */
export function renderFrontMatter(fm) {
  if (!fm || fm.raw === null) return '';

  if (fm.data && typeof fm.data === 'object' && !Array.isArray(fm.data)) {
    const rows = Object.entries(fm.data)
      .map(([k, v]) => `<tr><th>${esc(k)}</th><td>${scalar(v)}</td></tr>`)
      .join('');
    if (rows) {
      return `<details class="frontmatter" open><summary>Front matter</summary>` +
             `<table><tbody>${rows}</tbody></table></details>`;
    }
  }

  const note = fm.error ? `<div class="fm-error">Could not parse: ${esc(fm.error)}</div>` : '';
  return `<details class="frontmatter" open><summary>Front matter</summary>` +
         `${note}<pre>${esc(fm.raw)}</pre></details>`;
}
