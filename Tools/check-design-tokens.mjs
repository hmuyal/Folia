/*
 * Verifies that the design spec and the implementation agree.
 *
 * docs/DESIGN-claude.md is the source of truth for colours, radii and spacing.
 * Those values are hand-transcribed into two places — web/styles/tokens.css for
 * the document, and Sources/MDApp/Design/Tokens.swift for native chrome — so
 * without a check they drift silently and the seam between chrome and content
 * starts to show.
 */
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const spec  = readFileSync(resolve(root, 'docs/DESIGN-claude.md'), 'utf8');
const css   = readFileSync(resolve(root, 'web/styles/tokens.css'), 'utf8');
const swift = readFileSync(resolve(root, 'Sources/MDApp/Design/Tokens.swift'), 'utf8');

/** Pulls a flat `key: value` block out of the spec's YAML front matter. */
function specBlock(name) {
  const match = spec.match(new RegExp(`^${name}:\\n((?:  \\S[^\\n]*\\n)+)`, 'm'));
  if (!match) return {};
  const out = {};
  for (const line of match[1].split('\n')) {
    const kv = line.match(/^ {2}([\w-]+):\s*"?([^"\n]+?)"?\s*$/);
    if (kv) out[kv[1]] = kv[2];
  }
  return out;
}

const colors  = specBlock('colors');
const rounded = specBlock('rounded');
const spacing = specBlock('spacing');

/** CSS custom-property names differ from the spec keys for radius and spacing. */
const cssName = { colors: (k) => `--${k}`, rounded: (k) => `--r-${k}`, spacing: (k) => `--s-${k}` };

const problems = [];
let checked = 0;

function checkCSS(group, entries) {
  for (const [key, value] of Object.entries(entries)) {
    const prop = cssName[group](key);
    // Only the first (light-theme :root) declaration is the token definition;
    // later ones are dark-theme overrides of derived tokens.
    const found = css.match(new RegExp(`${prop.replace(/[-]/g, '\\-')}\\s*:\\s*([^;]+);`));
    checked++;
    if (!found) {
      problems.push(`tokens.css is missing ${prop} (spec ${group}.${key} = ${value})`);
    } else if (found[1].trim().toLowerCase() !== value.toLowerCase()) {
      problems.push(`tokens.css ${prop} = ${found[1].trim()} but spec says ${value}`);
    }
  }
}

checkCSS('colors', colors);
checkCSS('rounded', rounded);
checkCSS('spacing', spacing);

/* Swift uses its own camelCase names and some abbreviations, so match on the
   literal value rather than the identifier. */
for (const [key, hex] of Object.entries(colors)) {
  const literal = `0x${hex.replace('#', '').toUpperCase()}`;
  checked++;
  if (!swift.includes(literal)) {
    problems.push(`Tokens.swift has no ${literal} (spec colors.${key} = ${hex})`);
  }
}
for (const [key, value] of Object.entries({ ...rounded, ...spacing })) {
  const number = value.replace('px', '');
  checked++;
  if (!new RegExp(`:\\s*CGFloat\\s*=\\s*${number}\\b`).test(swift)) {
    problems.push(`Tokens.swift has no CGFloat = ${number} (spec ${key} = ${value})`);
  }
}

if (problems.length) {
  console.error('✗ design tokens out of sync with docs/DESIGN-claude.md');
  for (const p of problems) console.error(`  ${p}`);
  process.exit(1);
}
console.log(`✓ design tokens match the spec (${checked} checks across CSS and Swift)`);
