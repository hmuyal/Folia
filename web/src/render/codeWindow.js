import hljs from 'highlight.js/lib/core';

/* A curated registry: every language is imported from lib/languages so the
   bundler sees exactly one copy. Importing highlight.js/lib/common instead
   pulls a second, ESM copy of every language it covers. */
import bash from 'highlight.js/lib/languages/bash';
import c from 'highlight.js/lib/languages/c';
import clojure from 'highlight.js/lib/languages/clojure';
import cpp from 'highlight.js/lib/languages/cpp';
import csharp from 'highlight.js/lib/languages/csharp';
import css from 'highlight.js/lib/languages/css';
import dart from 'highlight.js/lib/languages/dart';
import diff from 'highlight.js/lib/languages/diff';
import dockerfile from 'highlight.js/lib/languages/dockerfile';
import elixir from 'highlight.js/lib/languages/elixir';
import erlang from 'highlight.js/lib/languages/erlang';
import fortran from 'highlight.js/lib/languages/fortran';
import go from 'highlight.js/lib/languages/go';
import graphql from 'highlight.js/lib/languages/graphql';
import groovy from 'highlight.js/lib/languages/groovy';
import haskell from 'highlight.js/lib/languages/haskell';
import ini from 'highlight.js/lib/languages/ini';
import java from 'highlight.js/lib/languages/java';
import javascript from 'highlight.js/lib/languages/javascript';
import json from 'highlight.js/lib/languages/json';
import julia from 'highlight.js/lib/languages/julia';
import kotlin from 'highlight.js/lib/languages/kotlin';
import latex from 'highlight.js/lib/languages/latex';
import less from 'highlight.js/lib/languages/less';
import lua from 'highlight.js/lib/languages/lua';
import makefile from 'highlight.js/lib/languages/makefile';
import markdown from 'highlight.js/lib/languages/markdown';
import matlab from 'highlight.js/lib/languages/matlab';
import nginx from 'highlight.js/lib/languages/nginx';
import objectivec from 'highlight.js/lib/languages/objectivec';
import perl from 'highlight.js/lib/languages/perl';
import php from 'highlight.js/lib/languages/php';
import plaintext from 'highlight.js/lib/languages/plaintext';
import powershell from 'highlight.js/lib/languages/powershell';
import protobuf from 'highlight.js/lib/languages/protobuf';
import python from 'highlight.js/lib/languages/python';
import r from 'highlight.js/lib/languages/r';
import ruby from 'highlight.js/lib/languages/ruby';
import rust from 'highlight.js/lib/languages/rust';
import scala from 'highlight.js/lib/languages/scala';
import scss from 'highlight.js/lib/languages/scss';
import shell from 'highlight.js/lib/languages/shell';
import sql from 'highlight.js/lib/languages/sql';
import swift from 'highlight.js/lib/languages/swift';
import typescript from 'highlight.js/lib/languages/typescript';
import vim from 'highlight.js/lib/languages/vim';
import wasm from 'highlight.js/lib/languages/wasm';
import xml from 'highlight.js/lib/languages/xml';
import yaml from 'highlight.js/lib/languages/yaml';

const LANGUAGES = {
  bash, c, clojure, cpp, csharp,
  css, dart, diff, dockerfile, elixir,
  erlang, fortran, go, graphql, groovy,
  haskell, ini, java, javascript, json,
  julia, kotlin, latex, less, lua,
  makefile, markdown, matlab, nginx, objectivec,
  perl, php, plaintext, powershell, protobuf,
  python, r, ruby, rust, scala,
  scss, shell, sql, swift, typescript,
  vim, wasm, xml, yaml,
};

for (const [name, lang] of Object.entries(LANGUAGES)) hljs.registerLanguage(name, lang);
hljs.registerLanguage('toml', ini);

const ALIASES = {
  js: 'javascript', ts: 'typescript', jsx: 'javascript', tsx: 'typescript',
  py: 'python', rb: 'ruby', sh: 'bash', zsh: 'bash', shell: 'bash',
  yml: 'yaml', md: 'markdown', tex: 'latex', 'c++': 'cpp', 'c#': 'csharp',
  golang: 'go', rs: 'rust', kt: 'kotlin', ps1: 'powershell', htm: 'xml',
  html: 'xml', vue: 'xml', jsonc: 'json', mjs: 'javascript', cjs: 'javascript',
};

const DISPLAY = {
  xml: 'HTML', cpp: 'C++', csharp: 'C#', objectivec: 'Objective-C',
  javascript: 'JavaScript', typescript: 'TypeScript', bash: 'Shell',
  json: 'JSON', yaml: 'YAML', css: 'CSS', scss: 'SCSS', sql: 'SQL',
  php: 'PHP', ini: 'INI', toml: 'TOML', graphql: 'GraphQL', latex: 'LaTeX', r: 'R',
};

export function escapeHTML(s) {
  return s.replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

/* Splits highlighted HTML into one <span class="cl"> per source line.
   hljs spans can straddle newlines (block comments, template literals), so the
   open-tag stack is closed at each break and re-opened on the next line. */
export function wrapLines(html) {
  const lines = [];
  const open = [];
  let cur = '';
  const re = /(<span\b[^>]*>)|(<\/span>)|(\n)|([^<\n]+|<)/g;
  let m;

  while ((m = re.exec(html)) !== null) {
    if (m[1])      { open.push(m[1]); cur += m[1]; }
    else if (m[2]) { open.pop();      cur += m[2]; }
    else if (m[3]) {
      cur += '</span>'.repeat(open.length);
      lines.push(cur);
      cur = open.join('');
    } else         { cur += m[4]; }
  }
  cur += '</span>'.repeat(open.length);
  lines.push(cur);

  return lines
    .map((l) => `<span class="cl">${l === '' ? '​' : l}</span>`)
    .join('');
}

export function highlightCode(code, lang, enabled) {
  const normalised = ALIASES[lang?.toLowerCase()] || lang?.toLowerCase() || '';
  if (!enabled || !normalised || !hljs.getLanguage(normalised)) {
    return { html: escapeHTML(code), resolved: normalised || null };
  }
  try {
    const out = hljs.highlight(code, { language: normalised, ignoreIllegals: true });
    return { html: out.value, resolved: normalised };
  } catch {
    return { html: escapeHTML(code), resolved: normalised };
  }
}

export function languageLabel(lang, resolved) {
  if (!lang) return 'Text';
  const key = resolved || ALIASES[lang.toLowerCase()] || lang.toLowerCase();
  return DISPLAY[key] || lang.charAt(0).toUpperCase() + lang.slice(1);
}

/* The `code-window-card` from DESIGN-claude.md: dark surface, chrome bar with
   language chip and copy button, inner code panel, optional gutter. */
export function codeWindowPlugin(md, getOpts) {
  md.renderer.rules.fence = (tokens, idx) => {
    const token = tokens[idx];
    const opts = getOpts();
    const info = token.info ? md.utils.unescapeAll(token.info).trim() : '';
    const lang = info.split(/\s+/)[0] || '';
    const code = token.content.replace(/\n$/, '');
    const line = token.map ? ` data-line="${token.map[0]}"` : '';

    if (opts.mermaid && /^mermaid$/i.test(lang)) {
      return `<div class="mermaid-block breakout" data-state="pending"${line}>` +
             `<pre class="mermaid-source" hidden>${escapeHTML(code)}</pre>` +
             `<div class="mermaid-target"></div></div>\n`;
    }

    const { html, resolved } = highlightCode(code, lang, opts.syntaxHighlight);
    const label = languageLabel(lang, resolved);

    return (
      `<figure class="code-window breakout"${line}` +
      ` data-numbers="${opts.lineNumbers ? 1 : 0}" data-wrap="${opts.wrapCode ? 1 : 0}"` +
      ` data-lang="${escapeHTML(lang)}">` +
        `<figcaption class="code-window__bar">` +
          `<span class="code-window__lang">${escapeHTML(label)}</span>` +
          `<button class="code-window__copy" type="button" data-copy>Copy</button>` +
        `</figcaption>` +
        `<div class="code-window__body"><pre><code class="hljs${resolved ? ` language-${resolved}` : ''}">` +
          wrapLines(html) +
        `</code></pre></div>` +
      `</figure>\n`
    );
  };

  /* Indented code blocks get the same treatment, minus the language chip. */
  md.renderer.rules.code_block = (tokens, idx) => {
    const token = tokens[idx];
    const opts = getOpts();
    const code = token.content.replace(/\n$/, '');
    const line = token.map ? ` data-line="${token.map[0]}"` : '';
    return (
      `<figure class="code-window breakout"${line}` +
      ` data-numbers="${opts.lineNumbers ? 1 : 0}" data-wrap="${opts.wrapCode ? 1 : 0}">` +
        `<div class="code-window__body"><pre><code class="hljs">` +
          wrapLines(escapeHTML(code)) +
        `</code></pre></div>` +
      `</figure>\n`
    );
  };
}

export { hljs };
