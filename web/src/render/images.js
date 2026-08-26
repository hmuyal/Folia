/* Rewrites image and link targets so the WebView never sees a file:// URL.

   folia://doc/<relative path>   -> resolved against the document's directory
   folia://file/<absolute path>  -> an absolute path on disk
   remote URLs                   -> left alone if allowed, neutralised if not   */

const REMOTE = /^(https?:)?\/\//i;
const DATA_URI = /^data:/i;

export function resolveAssetURL(src, opts) {
  if (!src) return src;
  if (DATA_URI.test(src)) return src;
  if (src.startsWith('folia://')) return src;

  if (REMOTE.test(src)) {
    return opts.allowRemoteContent ? src : `folia://blocked/${encodeURIComponent(src)}`;
  }
  if (!opts.inlineImages) return `folia://blocked/${encodeURIComponent(src)}`;

  let path = src;
  if (path.startsWith('file://')) {
    try { path = decodeURI(new URL(path).pathname); } catch { /* keep as-is */ }
  }
  if (path.startsWith('~/')) return `folia://home/${encodePath(path.slice(2))}`;
  if (path.startsWith('/'))  return `folia://file/${encodePath(path.slice(1))}`;
  return `folia://doc/${encodePath(path)}`;
}

function encodePath(p) {
  const [bare, hash] = splitHash(p);
  return bare.split('/').map(encodeURIComponent).join('/') + hash;
}

function splitHash(p) {
  const i = p.indexOf('#');
  return i === -1 ? [p, ''] : [p.slice(0, i), p.slice(i)];
}

export function imagesPlugin(md, getOpts) {
  const defaultImage = md.renderer.rules.image ||
    ((tokens, idx, o, env, self) => self.renderToken(tokens, idx, o));

  md.renderer.rules.image = (tokens, idx, o, env, self) => {
    const token = tokens[idx];
    const opts = getOpts();
    const srcIdx = token.attrIndex('src');
    if (srcIdx >= 0) {
      const original = token.attrs[srcIdx][1];
      token.attrs[srcIdx][1] = resolveAssetURL(original, opts);
      token.attrSet('data-src-original', original);
      token.attrSet('loading', 'lazy');
    }
    return defaultImage(tokens, idx, o, env, self);
  };

  /* Links: http(s) are handed to Swift, which opens the default browser.
     Anything with a dangerous scheme is defanged. */
  const defaultLinkOpen = md.renderer.rules.link_open ||
    ((tokens, idx, o, env, self) => self.renderToken(tokens, idx, o));

  md.renderer.rules.link_open = (tokens, idx, o, env, self) => {
    const token = tokens[idx];
    const hrefIdx = token.attrIndex('href');
    if (hrefIdx >= 0) {
      const href = token.attrs[hrefIdx][1] || '';
      if (/^\s*javascript:/i.test(href) || /^\s*vbscript:/i.test(href) || /^\s*data:text\/html/i.test(href)) {
        token.attrs[hrefIdx][1] = '#';
        token.attrSet('data-blocked', '1');
      } else if (REMOTE.test(href) || /^mailto:/i.test(href)) {
        token.attrSet('data-external', '1');
      } else if (!href.startsWith('#')) {
        token.attrSet('data-internal', '1');
      }
    }
    return defaultLinkOpen(tokens, idx, o, env, self);
  };
}
