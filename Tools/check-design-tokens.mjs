/*
 * Verifies that the design tokens and their native-chrome mirror agree.
 *
 * Colours, radii and spacing are hand-transcribed into two places —
 * web/styles/tokens.css for the document, and Sources/Folia/Design/Tokens.swift
 * for native chrome — so without a check they drift silently and the seam
 * between chrome and content starts to show.
 */
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const css   = readFileSync(resolve(root, 'web/styles/tokens.css'), 'utf8');
const swift = readFileSync(resolve(root, 'Sources/Folia/Design/Tokens.swift'), 'utf8');

const COLOR_KEYS = [
  'primary', 'primary-active', 'primary-disabled', 'ink', 'body', 'body-strong',
  'muted', 'muted-soft', 'hairline', 'hairline-soft', 'canvas', 'surface-soft',
  'surface-card', 'surface-cream-strong', 'surface-dark', 'surface-dark-elevated',
  'surface-dark-soft', 'on-primary', 'on-dark', 'on-dark-soft', 'accent-teal',
  'accent-amber', 'success', 'warning', 'error',
];
const ROUNDED_KEYS = ['xs', 'sm', 'md', 'lg', 'xl', 'pill', 'full'];
const SPACING_KEYS = ['xxs', 'xs', 'sm', 'md', 'lg', 'xl', 'xxl', 'section'];

/** Reads a CSS custom property's value out of the file's first :root block. */
function cssValue(prop) {
  const found = css.match(new RegExp(`${prop.replace(/-/g, '\\-')}\\s*:\\s*([^;]+);`));
  return found ? found[1].trim() : null;
}

const problems = [];
let checked = 0;

function readGroup(keys, prefix) {
  const out = {};
  for (const key of keys) {
    const value = cssValue(`--${prefix}${key}`);
    checked++;
    if (!value) { problems.push(`tokens.css is missing --${prefix}${key}`); continue; }
    out[key] = value;
  }
  return out;
}

const colors  = readGroup(COLOR_KEYS, '');
const rounded = readGroup(ROUNDED_KEYS, 'r-');
const spacing = readGroup(SPACING_KEYS, 's-');

/* Swift uses its own camelCase names and some abbreviations, so match on the
   literal value rather than the identifier. */
for (const [key, hex] of Object.entries(colors)) {
  const literal = `0x${hex.replace('#', '').toUpperCase()}`;
  checked++;
  if (!swift.includes(literal)) {
    problems.push(`Tokens.swift has no ${literal} (tokens.css --${key} = ${hex})`);
  }
}
for (const [key, value] of Object.entries({ ...rounded, ...spacing })) {
  const number = value.replace('px', '');
  checked++;
  if (!new RegExp(`:\\s*CGFloat\\s*=\\s*${number}\\b`).test(swift)) {
    problems.push(`Tokens.swift has no CGFloat = ${number} (tokens.css value ${value} for ${key})`);
  }
}

if (problems.length) {
  console.error('✗ design tokens out of sync between tokens.css and Tokens.swift');
  for (const p of problems) console.error(`  ${p}`);
  process.exit(1);
}
console.log(`✓ design tokens match (${checked} checks across CSS and Swift)`);
