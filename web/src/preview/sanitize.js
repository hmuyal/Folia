import DOMPurify from 'dompurify';

/* mdapp: must survive — every local image src uses it. */
const URI_OK = /^(?:(?:https?|mailto|tel|mdapp):|[^a-z]|[a-z+.-]+(?:[^a-z+.\-:]|$))/i;

const CONFIG = {
  /* data-* is allowed wholesale (ALLOW_DATA_ATTR defaults true), which covers
     data-line, data-lang, data-copy and friends. */
  FORBID_TAGS: ['script', 'style', 'iframe', 'frame', 'frameset', 'object',
                'embed', 'applet', 'form', 'link', 'meta', 'base', 'noscript'],
  FORBID_ATTR: ['srcset', 'ping', 'formaction', 'form', 'action'],
  ALLOWED_URI_REGEXP: URI_OK,
  ADD_ATTR: ['target', 'loading', 'align', 'checked', 'disabled', 'open', 'start'],
  KEEP_CONTENT: true,
};

let hooked = false;
function installHooks() {
  if (hooked) return;
  hooked = true;
  /* Anything that survives with an href leaves through Swift, never in-page. */
  DOMPurify.addHook('afterSanitizeAttributes', (node) => {
    if (node.hasAttribute?.('href')) {
      const href = node.getAttribute('href') || '';
      if (/^(https?|mailto|tel):/i.test(href)) node.setAttribute('data-external', '1');
    }
  });
}

export function sanitizeHTML(html) {
  installHooks();
  return DOMPurify.sanitize(html, CONFIG);
}

export { DOMPurify };
