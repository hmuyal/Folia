/* Stamps data-line onto every top-level block token so the preview can be
   mapped back to editor lines for bidirectional scroll sync. */

const BLOCKS = [
  'paragraph_open', 'heading_open', 'blockquote_open', 'bullet_list_open',
  'ordered_list_open', 'table_open', 'hr', 'dl_open', 'admonition_open',
  'footnote_block_open', 'container_note_open',
];

export function lineMapPlugin(md) {
  md.core.ruler.push('line_map', (state) => {
    for (const token of state.tokens) {
      if (token.map && (BLOCKS.includes(token.type) || token.block)) {
        token.attrSet('data-line', String(token.map[0]));
      }
    }
    return true;
  });
}
