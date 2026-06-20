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
await writeFile(join(outDir, '_redirects'), [
  '/app  https://stemacle.com/app  301',
  '/app/* https://stemacle.com/app/:splat  301',
  '/stem-player  https://stemacle.com/app  301',
  '/stem-player/* https://stemacle.com/app/:splat 301',
].join('\n'));
await writeFile(join(outDir, 'app', 'index.html'), `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="robots" content="noindex" />
    <meta http-equiv="refresh" content="0; url=https://stemacle.com/app" />
    <script>
      (function redirectAppEntry() {
        const path = window.location.pathname || '';
        const tail = path.replace(/^\\/app\\/?/, '');
        const suffix = tail ? '/' + tail : '';
        const destination = `https://stemacle.com/app${suffix}${window.location.search}${window.location.hash}`;
        window.location.replace(destination);
      })();
    </script>
    <title>Redirecting to Stemacle Web App</title>
  </head>
  <body>
    <p>Redirecting to <a href="https://stemacle.com/app">stemacle.com/app</a>.</p>
  </body>
</html>`);
await cp(join(root, '404.html'), join(outDir, '404.html'));
await mkdir(join(outDir, 'stem-player'), { recursive: true });
await writeFile(join(outDir, 'stem-player', 'index.html'), `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="robots" content="noindex" />
    <meta http-equiv="refresh" content="0; url=https://stemacle.com/app" />
    <script>
      (function redirectStemPlayer() {
        const tail = window.location.pathname.replace(/^\\/stem-player\\/?/, '');
        const suffix = tail ? '/' + tail : '';
        const destination = 'https://stemacle.com/app' + suffix + window.location.search + window.location.hash;
        window.location.replace(destination);
      })();
    </script>
    <title>Redirecting to Stemacle Web App</title>
  </head>
  <body>
    <p>Redirecting to <a href="https://stemacle.com/app">stemacle.com/app</a>.</p>
  </body>
</html>`);

console.log(`Prepared Stemacle Pages bundle at ${outDir}`);
