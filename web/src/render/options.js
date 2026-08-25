/* Extension + option schema. Mirrors QLMarkdown's settings pane one-for-one so
   the Settings window can be generated from this list. */

export const DEFAULT_OPTIONS = {
  /* --- cmark-gfm equivalents --- */
  table:            true,
  strikethrough:    true,
  taskList:         true,
  autolink:         true,
  footnotes:        true,
  allowHTML:        true,   // parse inline/block HTML (GitHub does; sanitised below)
  sanitizeHTML:     true,   // run the result through DOMPurify

  /* --- QLMarkdown's custom extensions --- */
  highlight:        true,   // ==mark==
  subscript:        true,   // ~sub~
  superscript:      true,   // ^sup^
  inserted:         true,   // ++ins++
  emoji:            true,
  headsAnchors:     true,
  yamlHeader:       true,
  inlineImages:     true,
  math:             true,
  mermaid:          true,
  syntaxHighlight:  true,

  /* --- extras beyond QLMarkdown --- */
  deflist:          true,
  abbr:             true,
  attrs:            true,
  containers:       true,
  alerts:           true,   // > [!NOTE]
  wikiLinks:        false,  // [[Page]]

  /* --- display options --- */
  lineNumbers:      true,
  wrapCode:         false,
  smartQuotes:      true,   // typographer: quotes, en/em dash, ellipsis
  hardBreak:        false,  // soft line break -> <br>
  noSoftBreak:      false,  // soft line break -> space
  renderAsSource:   false,
  tocDepth:         3,

  /* --- security --- */
  allowRemoteContent:  false,
};

/* Groups drive the Settings UI layout. */
export const OPTION_GROUPS = [
  { title: 'Markdown extensions', keys: [
    'table','strikethrough','taskList','autolink','footnotes',
    'highlight','subscript','superscript','inserted','emoji',
    'deflist','abbr','attrs','containers','alerts','wikiLinks' ] },
  { title: 'Document structure', keys: [
    'headsAnchors','yamlHeader','inlineImages' ] },
  { title: 'Rich content', keys: [
    'math','mermaid','syntaxHighlight','lineNumbers','wrapCode' ] },
  { title: 'Typography', keys: [
    'smartQuotes','hardBreak','noSoftBreak','renderAsSource' ] },
  { title: 'Security', keys: [
    'allowHTML','sanitizeHTML','allowRemoteContent' ] },
];

export const OPTION_LABELS = {
  table:            ['Tables', 'GitHub pipe-table syntax'],
  strikethrough:    ['Strikethrough', '~~text~~'],
  taskList:         ['Task lists', '- [ ] and - [x] checkboxes'],
  autolink:         ['Autolink', 'Turn bare URLs and emails into links'],
  footnotes:        ['Footnotes', 'text[^1] with [^1]: definitions'],
  allowHTML:        ['Allow HTML', 'Render inline HTML instead of escaping it'],
  sanitizeHTML:     ['Sanitise HTML', 'Strip scripts, event handlers and unsafe URLs'],
  highlight:        ['Highlight', '==marked text=='],
  subscript:        ['Subscript', '~text~'],
  superscript:      ['Superscript', '^text^'],
  inserted:         ['Inserted', '++underlined++'],
  emoji:            ['Emoji', 'Convert :shortcodes: to glyphs'],
  headsAnchors:     ['Heading anchors', 'Linkable #slug for every heading'],
  yamlHeader:       ['YAML front matter', 'Render --- metadata --- as a table'],
  inlineImages:     ['Local images', 'Load images from paths next to the document'],
  math:             ['Math', 'LaTeX via $…$ and $$…$$, rendered with KaTeX'],
  mermaid:          ['Mermaid diagrams', 'Render ```mermaid code blocks'],
  syntaxHighlight:  ['Syntax highlighting', 'Colour code blocks'],
  deflist:          ['Definition lists', 'Term / : definition'],
  abbr:             ['Abbreviations', '*[HTML]: HyperText Markup Language'],
  attrs:            ['Attributes', '{.class #id} on elements'],
  containers:       ['Containers', ':::note fenced blocks'],
  alerts:           ['GitHub alerts', '> [!NOTE], [!TIP], [!WARNING]…'],
  wikiLinks:        ['Wiki links', '[[Page name]] links between files'],
  lineNumbers:      ['Line numbers', 'Show a gutter in code blocks'],
  wrapCode:         ['Wrap code', 'Wrap long lines instead of scrolling'],
  smartQuotes:      ['Smart typography', 'Curly quotes, en/em dashes, ellipses'],
  hardBreak:        ['Hard breaks', 'Treat every newline as a line break'],
  noSoftBreak:      ['No soft breaks', 'Collapse newlines into spaces'],
  renderAsSource:   ['Render as source', 'Show the raw text, syntax-highlighted'],
  allowRemoteContent:['Allow remote content', 'Let the document load images from the network'],
};
