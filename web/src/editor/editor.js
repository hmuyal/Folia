import { EditorState, Compartment, EditorSelection } from '@codemirror/state';
import {
  EditorView, keymap, lineNumbers, highlightActiveLine, highlightActiveLineGutter,
  drawSelection, dropCursor, rectangularSelection, crosshairCursor, placeholder,
} from '@codemirror/view';
import { defaultKeymap, history, historyKeymap, indentWithTab } from '@codemirror/commands';
import { indentOnInput, bracketMatching, foldGutter, foldKeymap, indentUnit } from '@codemirror/language';
import { closeBrackets, closeBracketsKeymap } from '@codemirror/autocomplete';
import {
  searchKeymap, highlightSelectionMatches, search,
  openSearchPanel, closeSearchPanel,
} from '@codemirror/search';
import { markdown, markdownLanguage } from '@codemirror/lang-markdown';
import { languages } from '@codemirror/language-data';

import { vim } from '@replit/codemirror-vim';
import { claudeEditorTheme, claudeSyntax } from './theme.js';
import { COMMANDS, continueList } from './commands.js';
import { handlePaste, handleDrop } from './paste.js';

/** The source pane. Owns the CodeMirror instance and its live configuration. */
export class Editor {
  constructor(parent, { onChange, onCursor, onScroll } = {}) {
    this.onChange = onChange ?? (() => {});
    this.onCursor = onCursor ?? (() => {});
    this.onScroll = onScroll ?? (() => {});

    this.compartments = {
      lineNumbers: new Compartment(),
      wrap:        new Compartment(),
      fontSize:    new Compartment(),
      tabSize:     new Compartment(),
      typewriter:  new Compartment(),
      vim:         new Compartment(),
    };

    this.suppressChange = false;
    this.lastCursorLine = -1;

    this.view = new EditorView({
      parent,
      state: EditorState.create({
        doc: '',
        extensions: this.extensions(),
      }),
    });
  }

  extensions() {
    const c = this.compartments;
    return [
      c.lineNumbers.of([lineNumbers(), highlightActiveLineGutter()]),
      c.wrap.of(EditorView.lineWrapping),
      c.fontSize.of(EditorView.theme({ '.cm-content, .cm-gutters': { fontSize: '14px' } })),
      c.tabSize.of(indentUnit.of('    ')),
      c.typewriter.of([]),
      c.vim.of([]),          // must precede the keymaps it overrides

      history(),
      drawSelection(),
      dropCursor(),
      EditorState.allowMultipleSelections.of(true),
      indentOnInput(),
      bracketMatching(),
      closeBrackets(),
      foldGutter({ openText: '⌄', closedText: '›' }),
      rectangularSelection(),
      crosshairCursor(),
      highlightActiveLine(),
      highlightSelectionMatches(),
      search({ top: true }),
      placeholder('Start writing…'),

      markdown({ base: markdownLanguage, codeLanguages: languages, addKeymap: false }),
      claudeEditorTheme,
      claudeSyntax,

      keymap.of([
        // Enter continues lists before CodeMirror's default newline runs.
        { key: 'Enter', run: continueList },
        { key: 'Mod-b', run: (v) => COMMANDS.bold(v) },
        { key: 'Mod-i', run: (v) => COMMANDS.italic(v) },
        { key: 'Mod-k', run: (v) => COMMANDS.link(v) },
        { key: 'Mod-e', run: (v) => COMMANDS.code(v) },
        { key: 'Mod-Shift-x', run: (v) => COMMANDS.strike(v) },
        { key: 'Mod-Shift-e', run: (v) => COMMANDS.codeBlock(v) },
        { key: "Mod-Shift-'", run: (v) => COMMANDS.quote(v) },
        { key: 'Mod-Shift-l', run: (v) => COMMANDS.bulletList(v) },
        { key: 'Mod-Alt-l',   run: (v) => COMMANDS.orderedList(v) },
        ...[1, 2, 3, 4, 5, 6].map((n) => ({
          key: `Mod-${n}`, run: (v) => COMMANDS[`heading${n}`](v),
        })),
        { key: 'Mod-0', run: (v) => COMMANDS.heading0(v) },
        indentWithTab,
        ...closeBracketsKeymap,
        ...searchKeymap,
        ...historyKeymap,
        ...defaultKeymap,
      ]),

      EditorView.domEventHandlers({
        paste: (event, view) => handlePaste(view, event) ? (event.preventDefault(), true) : false,
        drop:  (event, view) => handleDrop(view, event)  ? (event.preventDefault(), true) : false,
        dragover: (event) => { event.preventDefault(); return false; },
        scroll: () => { this.reportScroll(); return false; },
      }),

      EditorView.updateListener.of((update) => {
        if (update.docChanged && !this.suppressChange) {
          this.onChange(update.state.doc.toString(), this.cursorLine());
        }
        if (update.selectionSet) {
          const line = this.cursorLine();
          if (line !== this.lastCursorLine) {
            this.lastCursorLine = line;
            this.onCursor(line);
          }
        }
      }),
    ];
  }

  // MARK: content

  get text() { return this.view.state.doc.toString(); }

  /** Replaces the whole document without emitting a change event. */
  setText(text, { cursorLine = 0, scrollLine = 0 } = {}) {
    this.suppressChange = true;
    this.view.dispatch({
      changes: { from: 0, to: this.view.state.doc.length, insert: text },
      selection: { anchor: 0 },
      annotations: [],
    });
    this.suppressChange = false;
    if (cursorLine > 0) this.setCursorLine(cursorLine);
    if (scrollLine > 0) this.scrollToLine(scrollLine);
  }

  /** Applies external text while keeping the cursor where it was. */
  replaceText(text) {
    if (text === this.text) return;
    const cursor = this.view.state.selection.main.head;
    this.suppressChange = true;
    this.view.dispatch({
      changes: { from: 0, to: this.view.state.doc.length, insert: text },
      selection: { anchor: Math.min(cursor, text.length) },
    });
    this.suppressChange = false;
  }

  // MARK: position

  cursorLine() {
    const head = this.view.state.selection.main.head;
    return this.view.state.doc.lineAt(head).number - 1;   // 0-based, as markdown-it reports
  }

  setCursorLine(line) {
    const n = Math.min(Math.max(line + 1, 1), this.view.state.doc.lines);
    const pos = this.view.state.doc.line(n).from;
    this.view.dispatch({ selection: EditorSelection.cursor(pos), scrollIntoView: true });
  }

  /** Fractional top line, so scroll sync is smooth rather than stepped. */
  topLine() {
    const view = this.view;
    const rect = view.scrollDOM.getBoundingClientRect();
    const pos = view.posAtCoords({ x: rect.left + 6, y: rect.top + 1 }, false);
    if (pos == null) return 0;

    const line = view.state.doc.lineAt(pos);
    const block = view.lineBlockAt(pos);
    // block.top is in document space; documentTop converts it to viewport space.
    const blockViewportTop = block.top + view.documentTop;
    const fraction = block.height > 0
      ? Math.min(1, Math.max(0, (rect.top - blockViewportTop) / block.height))
      : 0;
    return (line.number - 1) + fraction;
  }

  scrollToLine(line, { center = false } = {}) {
    const n = Math.min(Math.max(Math.round(line) + 1, 1), this.view.state.doc.lines);
    const pos = this.view.state.doc.line(n).from;
    this.view.dispatch({
      effects: EditorView.scrollIntoView(pos, { y: center ? 'center' : 'start' }),
    });
  }

  /**
   * Puts `line` at the very top of the viewport. Driven continuously by
   * preview -> editor sync, so it adjusts scrollTop by a measured delta rather
   * than trusting any absolute coordinate space.
   */
  scrollLineToTop(line) {
    const view = this.view;
    const doc = view.state.doc;
    const n = Math.min(Math.max(Math.floor(line) + 1, 1), doc.lines);
    const block = view.lineBlockAt(doc.line(n).from);
    const fraction = Math.min(1, Math.max(0, line - Math.floor(line)));
    const rect = view.scrollDOM.getBoundingClientRect();
    const blockViewportTop = block.top + view.documentTop;
    const delta = (blockViewportTop - rect.top) + block.height * fraction;
    view.scrollDOM.scrollTop += delta;
  }

  reportScroll() {
    if (this.suppressScroll) return;
    this.onScroll(this.topLine());
  }

  // MARK: configuration

  setPrefs({ fontSize, tabWidth, lineNumbers: showNumbers, wrap, typewriter, vimMode }) {
    const effects = [];
    const c = this.compartments;

    if (fontSize != null) {
      effects.push(c.fontSize.reconfigure(EditorView.theme({
        '.cm-content, .cm-gutters': { fontSize: `${fontSize}px` },
      })));
    }
    if (tabWidth != null) {
      effects.push(c.tabSize.reconfigure(indentUnit.of(' '.repeat(tabWidth))));
    }
    if (showNumbers != null) {
      effects.push(c.lineNumbers.reconfigure(
        showNumbers ? [lineNumbers(), highlightActiveLineGutter()] : []));
    }
    if (wrap != null) {
      effects.push(c.wrap.reconfigure(wrap ? EditorView.lineWrapping : []));
    }
    if (typewriter != null) {
      effects.push(c.typewriter.reconfigure(typewriter ? typewriterExtension() : []));
    }
    if (vimMode != null) {
      effects.push(c.vim.reconfigure(vimMode ? vim({ status: true }) : []));
    }
    if (effects.length) this.view.dispatch({ effects });
  }

  run(command) {
    if (command === 'find')    { openSearchPanel(this.view); return true; }
    if (command === 'replace') { openSearchPanel(this.view); return true; }
    if (command === 'closeFind') { closeSearchPanel(this.view); return true; }
    const fn = COMMANDS[command];
    if (!fn) return false;
    return fn(this.view);
  }

  focus() { this.view.focus(); }
  get scrollElement() { return this.view.scrollDOM; }
}

/** Keeps the caret vertically centred as you type. */
function typewriterExtension() {
  return EditorView.updateListener.of((update) => {
    if (!update.docChanged && !update.selectionSet) return;
    const view = update.view;
    const head = view.state.selection.main.head;
    const block = view.lineBlockAt(head);
    const target = block.top - view.scrollDOM.clientHeight / 2 + block.height / 2;
    view.scrollDOM.scrollTop = Math.max(0, target);
  });
}
