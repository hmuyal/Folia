/* Fails the build if the Swift RenderOptions and the JS option schema drift.
   They are serialised into each other, so a silent mismatch would show up as
   an option that quietly stops working. */
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const { DEFAULT_OPTIONS } = await import(resolve(root, 'web/src/render/options.js'));

const swift = readFileSync(resolve(root, 'Sources/Folia/Services/Preferences.swift'), 'utf8');
const block = swift.match(/enum CodingKeys: String, CodingKey \{([\s\S]*?)\n {4}\}/)?.[1] ?? '';

const swiftKeys = new Set();
for (const line of block.split('\n')) {
  const trimmed = line.trim();
  if (!trimmed.startsWith('case ')) continue;
  for (const part of trimmed.slice(5).split(',')) {
    const m = part.trim().match(/^(\w+)(?:\s*=\s*"([^"]+)")?$/);
    if (m) swiftKeys.add(m[2] ?? m[1]);
  }
}

const jsKeys = new Set(Object.keys(DEFAULT_OPTIONS));
const onlyJS    = [...jsKeys].filter((k) => !swiftKeys.has(k));
const onlySwift = [...swiftKeys].filter((k) => !jsKeys.has(k));

if (onlyJS.length || onlySwift.length) {
  console.error('✗ RenderOptions parity check failed');
  if (onlyJS.length)    console.error('  in options.js but not Preferences.swift:', onlyJS.join(', '));
  if (onlySwift.length) console.error('  in Preferences.swift but not options.js:', onlySwift.join(', '));
  process.exit(1);
}
console.log(`✓ render options in sync (${jsKeys.size} keys)`);
