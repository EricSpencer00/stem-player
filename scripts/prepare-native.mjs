import { cp, mkdir, rm } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const outDir = join(root, 'dist', 'native');

async function copyIntoBundle(from, to = from) {
  await cp(join(root, from), join(outDir, to), {
    recursive: true,
    force: true,
    errorOnExist: false,
  });
}

await rm(outDir, { recursive: true, force: true });
await mkdir(outDir, { recursive: true });

await cp(join(root, 'native', 'index.html'), join(outDir, 'index.html'));
await copyIntoBundle('app');
await copyIntoBundle('apps');
await copyIntoBundle('privacy');
await copyIntoBundle('support');
await copyIntoBundle('assets');
await copyIntoBundle('samples');

console.log(`Prepared native Stemacle bundle at ${outDir}`);
