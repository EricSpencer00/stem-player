import { cp, mkdir, rm, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const outDir = join(root, 'dist', 'site');

async function copyIntoSite(from, to = from) {
  await cp(join(root, from), join(outDir, to), {
    recursive: true,
    force: true,
    errorOnExist: false,
  });
}

await rm(outDir, { recursive: true, force: true });
await mkdir(outDir, { recursive: true });

await cp(join(root, 'index.html'), join(outDir, 'index.html'));
await copyIntoSite('app');
await copyIntoSite('apps');
await copyIntoSite('assets');
await copyIntoSite('samples');
await writeFile(join(outDir, '_headers'), [
  '/app/*',
  '  Cross-Origin-Embedder-Policy: credentialless',
  '  Cross-Origin-Opener-Policy: same-origin',
  '',
].join('\n'));

console.log(`Prepared Stemacle Pages bundle at ${outDir}`);
