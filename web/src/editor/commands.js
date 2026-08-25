import { EditorSelection } from '@codemirror/state';

/* Markdown formatting commands. Each is a plain function of an EditorView so
   they can be driven from the menu bar, a shortcut, or a toolbar button. */

/** Wraps (or unwraps) each selection range with `before`/`after`. */
function toggleWrap(view, before, after = before) {
  const { state } = view;
  const changes = [];
  const ranges = [];

  for (const range of state.selection.ranges) {
    let { from, to } = range;

    // An empty selection wraps the word under the cursor, if there is one.
    if (from === to) {
      const line = state.doc.lineAt(from);
      const text = line.text;
      let s = from - line.from, e = s;
      const isWord = (c) => c && /[\w'’-]/.test(c);
      while (s > 0 && isWord(text[s - 1])) s--;
      while (e < text.length && isWord(text[e])) e++;
      if (e > s) { from = line.from + s; to = line.from + e; }
    }

    const selected = state.sliceDoc(from, to);
    const outer = state.sliceDoc(
      Math.max(0, from - before.length), Math.min(state.doc.length, to + after.length));

    if (selected.startsWith(before) && selected.endsWith(after) &&
        selected.length >= before.length + after.length) {
      // Markers inside the selection: strip them.
      const inner = selected.slice(before.length, selected.length - after.length);
      changes.push({ from, to, insert: inner });
      ranges.push(EditorSelection.range(from, from + inner.length));
    } else if (outer === before + selected + after) {
      // Markers just outside the selection: strip those instead.
      changes.push({ from: from - before.length, to: to + after.length, insert: selected });
      ranges.push(EditorSelection.range(from - before.length,
                                        from - before.length + selected.length));
    } else {
      changes.push({ from, to, insert: before + selected + after });
      ranges.push(EditorSelection.range(from + before.length,
                                        from + before.length + selected.length));
    }
  }

  view.dispatch({ changes, selection: EditorSelection.create(ranges), scrollIntoView: true });
  view.focus();
  return true;
}

/** Rewrites the prefix of every line the selection touches. */
function transformLines(view, fn) {
  const { state } = view;
  const changes = [];
  const seen = new Set();

  for (const range of state.selection.ranges) {
    const first = state.doc.lineAt(range.from).number;
    const last = state.doc.lineAt(range.to).number;
    for (let n = first; n <= last; n++) {
      if (seen.has(n)) continue;
      seen.add(n);
      const line = state.doc.line(n);
      const next = fn(line.text, n - first, line);
      if (next !== line.text) {
        changes.push({ from: line.from, to: line.to, insert: next });
      }
    }
  }
  if (changes.length) view.dispatch({ changes, scrollIntoView: true });
  view.focus();
  return true;
}

const HEADING = /^(#{1,6})\s+/;
const BULLET = /^(\s*)([-*+])\s+/;
const ORDERED = /^(\s*)(\d+)([.)])\s+/;
const TASK = /^(\s*)([-*+])\s+\[([ xX])\]\s+/;
const QUOTE = /^(\s*)>\s?/;

export function setHeading(view, level) {
  return transformLines(view, (text) => {
    const bare = text.replace(HEADING, '');
    if (level === 0) return bare;
    const prefix = '#'.repeat(level) + ' ';
    // Re-applying the same level removes it, so ⌘2 twice is a toggle.
    const current = HEADING.exec(text);
    if (current && current[1].length === level) return bare;
    return prefix + bare;
  });
}

export function toggleBulletList(view) {
  const allBullets = everyLine(view, (t) => BULLET.test(t) && !TASK.test(t));
  return transformLines(view, (text) => {
    if (allBullets) return text.replace(BULLET, '$1');
    if (TASK.test(text)) return text.replace(TASK, '$1- ');
    if (ORDERED.test(text)) return text.replace(ORDERED, '$1- ');
    if (BULLET.test(text)) return text;
    return text.trim() === '' ? text : text.replace(/^(\s*)/, '$1- ');
  });
}

export function toggleOrderedList(view) {
  const allOrdered = everyLine(view, (t) => ORDERED.test(t));
  return transformLines(view, (text, i) => {
    if (allOrdered) return text.replace(ORDERED, '$1');
    if (TASK.test(text)) return text.replace(TASK, `$1${i + 1}. `);
    if (BULLET.test(text)) return text.replace(BULLET, `$1${i + 1}. `);
    if (ORDERED.test(text)) return text;
    return text.trim() === '' ? text : text.replace(/^(\s*)/, `$1${i + 1}. `);
  });
}

export function toggleTaskList(view) {
  const allTasks = everyLine(view, (t) => TASK.test(t));
  return transformLines(view, (text) => {
    if (allTasks) return text.replace(TASK, '$1');
    if (BULLET.test(text)) return text.replace(BULLET, '$1- [ ] ');
    if (ORDERED.test(text)) return text.replace(ORDERED, '$1- [ ] ');
    return text.trim() === '' ? text : text.replace(/^(\s*)/, '$1- [ ] ');
  });
}

export function toggleQuote(view) {
  const allQuoted = everyLine(view, (t) => QUOTE.test(t));
  return transformLines(view, (text) =>
    allQuoted ? text.replace(QUOTE, '$1') : text.replace(/^(\s*)/, '$1> '));
}

function everyLine(view, predicate) {
  const { state } = view;
  let all = true, any = false;
  for (const range of state.selection.ranges) {
    const first = state.doc.lineAt(range.from).number;
    const last = state.doc.lineAt(range.to).number;
    for (let n = first; n <= last; n++) {
      const text = state.doc.line(n).text;
      if (text.trim() === '') continue;
      any = true;
      if (!predicate(text)) all = false;
    }
  }
  return any && all;
}

export function insertLink(view) {
  const { state } = view;
  const range = state.selection.main;
  const selected = state.sliceDoc(range.from, range.to);

  // Pasting a URL over a selection is the common case, so detect one on the
  // clipboard-free path too: if the selection *is* a URL, use it as the target.
  const isURL = /^(https?:\/\/|mailto:|\/|\.\/|#)/i.test(selected.trim());
  const text = isURL ? '' : selected;
  const href = isURL ? selected.trim() : '';
  const insert = `[${text}](${href})`;

  const cursor = isURL
    ? range.from + 1                                  // inside the empty label
    : range.from + text.length + 3;                   // inside the empty target

  view.dispatch({
    changes: { from: range.from, to: range.to, insert },
    selection: EditorSelection.cursor(cursor),
    scrollIntoView: true,
  });
  view.focus();
  return true;
}

export function insertCodeBlock(view) {
  const { state } = view;
  const range = state.selection.main;
  const selected = state.sliceDoc(range.from, range.to);
  const line = state.doc.lineAt(range.from);
  const atLineStart = range.from === line.from;
  const lead = atLineStart ? '' : '\n';

  const insert = `${lead}\`\`\`\n${selected}\n\`\`\`\n`;
  view.dispatch({
    changes: { from: range.from, to: range.to, insert },
    selection: EditorSelection.cursor(range.from + lead.length + 3),
    scrollIntoView: true,
  });
  view.focus();
  return true;
}

export function insertTable(view) {
  const range = view.state.selection.main;
  const line = view.state.doc.lineAt(range.from);
  const lead = range.from === line.from ? '' : '\n';
  const table = `${lead}| Column | Column |\n|---|---|\n|  |  |\n`;
  view.dispatch({
    changes: { from: range.from, to: range.to, insert: table },
    selection: EditorSelection.cursor(range.from + lead.length + 2),
    scrollIntoView: true,
  });
  view.focus();
  return true;
}

export function insertHorizontalRule(view) {
  const range = view.state.selection.main;
  const line = view.state.doc.lineAt(range.from);
  const lead = range.from === line.from ? '' : '\n';
  const insert = `${lead}\n---\n\n`;
  view.dispatch({
    changes: { from: range.from, to: range.to, insert },
    selection: EditorSelection.cursor(range.from + insert.length),
    scrollIntoView: true,
  });
  view.focus();
  return true;
}

/** Inserts an image reference, used by paste and drop handlers. */
export function insertImage(view, path, alt = '') {
  const range = view.state.selection.main;
  const insert = `![${alt}](${path})`;
  view.dispatch({
    changes: { from: range.from, to: range.to, insert },
    selection: EditorSelection.cursor(range.from + insert.length),
    scrollIntoView: true,
  });
  view.focus();
  return true;
}

/**
 * Enter inside a list continues it; Enter on an empty item ends the list
 * instead of leaving a dangling bullet.
 */
export function continueList(view) {
  const { state } = view;
  const range = state.selection.main;
  if (!range.empty) return false;

  const line = state.doc.lineAt(range.head);
  const text = line.text;

  const task = TASK.exec(text);
  const bullet = !task && BULLET.exec(text);
  const ordered = !task && !bullet && ORDERED.exec(text);
  if (!task && !bullet && !ordered) return false;

  const marker = task ? `${task[1]}${task[2]} [ ] `
              : bullet ? `${bullet[1]}${bullet[2]} `
              : `${ordered[1]}${Number(ordered[2]) + 1}${ordered[3]} `;

  const contentStart = line.from + (task ? task[0].length
                                   : bullet ? bullet[0].length
                                   : ordered[0].length);

  // Empty item: clear it rather than adding another.
  if (range.head >= contentStart && line.text.slice(contentStart - line.from).trim() === '') {
    view.dispatch({
      changes: { from: line.from, to: line.to, insert: '' },
      selection: EditorSelection.cursor(line.from),
    });
    return true;
  }

  view.dispatch({
    changes: { from: range.head, to: range.head, insert: '\n' + marker },
    selection: EditorSelection.cursor(range.head + 1 + marker.length),
    scrollIntoView: true,
  });
  return true;
}

export const COMMANDS = {
  bold:        (v) => toggleWrap(v, '**'),
  italic:      (v) => toggleWrap(v, '*'),
  strike:      (v) => toggleWrap(v, '~~'),
  code:        (v) => toggleWrap(v, '`'),
  highlight:   (v) => toggleWrap(v, '=='),
  link:        insertLink,
  quote:       toggleQuote,
  bulletList:  toggleBulletList,
  orderedList: toggleOrderedList,
  taskList:    toggleTaskList,
  codeBlock:   insertCodeBlock,
  table:       insertTable,
  hr:          insertHorizontalRule,
  heading0:    (v) => setHeading(v, 0),
  heading1:    (v) => setHeading(v, 1),
  heading2:    (v) => setHeading(v, 2),
  heading3:    (v) => setHeading(v, 3),
  heading4:    (v) => setHeading(v, 4),
  heading5:    (v) => setHeading(v, 5),
  heading6:    (v) => setHeading(v, 6),
};
