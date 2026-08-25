import { EditorView } from '@codemirror/view';
import { HighlightStyle, syntaxHighlighting } from '@codemirror/language';
import { tags as t } from '@lezer/highlight';

/* Every colour is a CSS custom property, so one theme definition serves both
   light and dark — the document's data-theme attribute drives it. */

export const claudeEditorTheme = EditorView.theme({
  '&': {
    color: 'var(--ed-text)',
    backgroundColor: 'var(--ed-bg)',
    height: '100%',
    fontFamily: 'var(--font-mono)',
  },
  '.cm-scroller': {
    fontFamily: 'var(--font-mono)',
    lineHeight: '1.65',
    padding: '20px 0 45vh 0',   // trailing space keeps the last line reachable
  },
  '.cm-content': {
    caretColor: 'var(--ed-cursor)',
    padding: '0',
  },
  '.cm-line': { padding: '0 18px' },

  '&.cm-focused': { outline: 'none' },
  '.cm-cursor, .cm-dropCursor': {
    borderLeftColor: 'var(--ed-cursor)',
    borderLeftWidth: '2px',
  },
  '&.cm-focused .cm-selectionBackgroundm, .cm-selectionBackground, .cm-content ::selection': {
    backgroundColor: 'var(--ed-selection)',
  },
  '.cm-activeLine': { backgroundColor: 'var(--ed-active-line)' },

  '.cm-gutters': {
    backgroundColor: 'var(--ed-gutter-bg)',
    color: 'var(--ed-gutter-text)',
    border: 'none',
    paddingRight: '4px',
    fontVariantNumeric: 'tabular-nums',
    fontSize: '0.85em',
  },
  '.cm-activeLineGutter': {
    backgroundColor: 'transparent',
    color: 'var(--ed-gutter-active)',
  },
  '.cm-foldPlaceholder': {
    backgroundColor: 'var(--ed-code-bg)',
    color: 'var(--ed-code)',
    border: 'none',
    borderRadius: '4px',
    padding: '0 6px',
  },

  '.cm-matchingBracket, &.cm-focused .cm-matchingBracket': {
    backgroundColor: 'var(--ed-matching)',
    outline: 'none',
  },
  '.cm-selectionMatch': { backgroundColor: 'var(--ed-search)' },
  '.cm-searchMatch': {
    backgroundColor: 'var(--ed-search)',
    borderRadius: '2px',
  },
  '.cm-searchMatch.cm-searchMatch-selected': {
    backgroundColor: 'var(--ed-search-active)',
  },

  /* Search / replace panel, restyled to match the app rather than the CM default */
  '.cm-panels': {
    backgroundColor: 'var(--ed-panel-bg)',
    color: 'var(--ed-text)',
    fontFamily: 'var(--font-body)',
    fontSize: '12px',
    borderTop: '1px solid var(--ed-divider)',
    borderBottom: '1px solid var(--ed-divider)',
  },
  '.cm-panel.cm-search': { padding: '8px 12px' },
  '.cm-panel.cm-search input[type=text]': {
    fontFamily: 'var(--font-body)',
    fontSize: '12px',
    padding: '4px 8px',
    borderRadius: '6px',
    border: '1px solid var(--ed-divider)',
    backgroundColor: 'var(--ed-bg)',
    color: 'var(--ed-text)',
  },
  '.cm-panel.cm-search button': {
    fontFamily: 'var(--font-body)',
    fontSize: '12px',
    backgroundImage: 'none',
    backgroundColor: 'transparent',
    border: '1px solid var(--ed-divider)',
    borderRadius: '6px',
    padding: '3px 9px',
    margin: '0 2px',
    color: 'var(--ed-text)',
    cursor: 'pointer',
  },
  '.cm-panel.cm-search label': { fontSize: '11px', color: 'var(--ed-quote)' },
  '.cm-panel.cm-search [name=close]': {
    fontSize: '16px',
    border: 'none',
    color: 'var(--ed-quote)',
  },

  '.cm-tooltip': {
    backgroundColor: 'var(--ed-panel-bg)',
    border: '1px solid var(--ed-divider)',
    borderRadius: '8px',
  },
}, { dark: false });

/* Markdown source highlighting. Headings step up in size the way they do in
   the rendered document, and the syntax punctuation recedes so the prose
   stays readable through the markup. */
export const claudeHighlightStyle = HighlightStyle.define([
  { tag: t.heading1, color: 'var(--ed-heading)', fontWeight: '700', fontSize: '1.32em' },
  { tag: t.heading2, color: 'var(--ed-heading)', fontWeight: '700', fontSize: '1.20em' },
  { tag: t.heading3, color: 'var(--ed-heading)', fontWeight: '600', fontSize: '1.10em' },
  { tag: t.heading4, color: 'var(--ed-heading)', fontWeight: '600' },
  { tag: [t.heading5, t.heading6], color: 'var(--ed-heading)', fontWeight: '600' },

  { tag: t.strong,   color: 'var(--ed-emphasis)', fontWeight: '700' },
  { tag: t.emphasis, color: 'var(--ed-emphasis)', fontStyle: 'italic' },
  { tag: t.strikethrough, textDecoration: 'line-through', color: 'var(--ed-quote)' },

  { tag: t.link,       color: 'var(--ed-link)' },
  { tag: t.url,        color: 'var(--ed-url)', textDecoration: 'underline' },
  { tag: t.monospace,  color: 'var(--ed-code)', backgroundColor: 'var(--ed-code-bg)' },
  { tag: t.quote,      color: 'var(--ed-quote)', fontStyle: 'italic' },
  { tag: t.list,       color: 'var(--ed-list)' },

  /* The markup characters themselves: #, *, `, >, - */
  { tag: t.processingInstruction, color: 'var(--ed-marker)' },
  { tag: t.contentSeparator, color: 'var(--ed-marker)', fontWeight: '600' },
  { tag: t.labelName, color: 'var(--ed-link)' },
  { tag: t.escape, color: 'var(--ed-marker)' },

  /* Fenced code blocks — the embedded language parser supplies these. */
  { tag: t.keyword,        color: 'var(--syn-keyword)' },
  { tag: [t.string, t.special(t.string)], color: 'var(--syn-string)' },
  { tag: [t.number, t.bool, t.null], color: 'var(--syn-number)' },
  { tag: [t.function(t.variableName), t.function(t.propertyName)], color: 'var(--syn-function)' },
  { tag: [t.typeName, t.className, t.namespace], color: 'var(--syn-type)' },
  { tag: [t.propertyName, t.attributeName], color: 'var(--syn-variable)' },
  { tag: t.comment,        color: 'var(--syn-comment)', fontStyle: 'italic' },
  { tag: [t.operator, t.punctuation, t.bracket], color: 'var(--syn-punct)' },
  { tag: t.meta,           color: 'var(--syn-meta)' },
  { tag: t.invalid,        color: 'var(--error)' },
]);

export const claudeSyntax = syntaxHighlighting(claudeHighlightStyle);
