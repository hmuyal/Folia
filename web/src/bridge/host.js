/* The only channel to Swift. Everything the page needs from the host goes
   through here, and nothing else touches window.webkit directly. */

const channel = window.webkit?.messageHandlers?.mdapp;
const asyncChannel = window.webkit?.messageHandlers?.mdappAsync;

/** True when running inside the app rather than the dev harness. */
export const isHosted = Boolean(channel);

function post(payload) {
  if (channel) channel.postMessage(payload);
  else console.debug('[host]', payload);
}

export const host = {
  ready:        ()                      => post({ type: 'ready' }),
  textChanged:  (id, text, cursorLine)  => post({ type: 'textChanged', id, text, cursorLine }),
  outline:      (items)                 => post({ type: 'outline', items }),
  cursor:       (line)                  => post({ type: 'cursor', line }),
  openExternal: (href)                  => post({ type: 'openExternal', href }),
  openRelative: (href)                  => post({ type: 'openRelative', href }),
  toggleTask:   (index, checked)        => post({ type: 'toggleTask', index, checked }),
  requestSave:  ()                      => post({ type: 'requestSave' }),
  stats:        (s)                     => post({ type: 'stats', ...s }),
  log:          (level, message)        => post({ type: 'log', level, message: String(message) }),

  /** Round-trips that need an answer (saving a pasted image, for example). */
  async request(type, payload = {}) {
    if (!asyncChannel) return null;
    try {
      return await asyncChannel.postMessage({ type, ...payload });
    } catch (err) {
      console.warn('[host] request failed', type, err);
      return null;
    }
  },
};

/* Surface page errors in the Swift log rather than losing them in a WebView
   with no visible console. */
window.addEventListener('error', (e) => {
  host.log('error', `${e.message} @ ${e.filename}:${e.lineno}`);
});
window.addEventListener('unhandledrejection', (e) => {
  host.log('error', `unhandled promise rejection: ${e.reason}`);
});
