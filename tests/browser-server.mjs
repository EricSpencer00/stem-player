// Static server helper used by the Puppeteer browser-parity tests.
//
// The tests need a real HTTP server because:
//   - the web app uses fetch() for the ONNX model (or falls back to DSP)
//   - the audio samples are loaded as relative URLs from app/index.html
//   - some browser APIs require a real origin (not file://)
//
// We serve the repository root so that /app/index.html, /native/index.html,
// and /samples/* all resolve correctly.

import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize, relative, resolve } from 'node:path';

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.mp3': 'audio/mpeg',
  '.wav': 'audio/wav',
  '.wasm': 'application/wasm',
  '.ico': 'image/x-icon',
  '.txt': 'text/plain; charset=utf-8',
  '.md': 'text/markdown; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
};

function fileForRequest(root, url) {
  const requestUrl = new URL(url, 'http://127.0.0.1');
  let pathname = decodeURIComponent(requestUrl.pathname);
  if (pathname === '/') pathname = '/index.html';
  if (pathname.endsWith('/')) pathname += 'index.html';
  const candidate = normalize(join(root, pathname));
  const rel = relative(root, candidate);
  // Reject any path that escapes the root.
  if (rel.startsWith('..') || rel.includes(`..${process.platform === 'win32' ? '\\' : '/'}`)) {
    return null;
  }
  if (!existsSync(candidate)) return null;
  const stats = statSync(candidate);
  if (!stats.isFile()) return null;
  return { path: candidate, size: stats.size, mime: MIME[extname(candidate).toLowerCase()] || 'application/octet-stream' };
}

export async function startStaticServer({ root, port = 0 } = {}) {
  const serverRoot = resolve(root || process.cwd());
  return new Promise((resolveServer, rejectServer) => {
    const server = createServer((req, res) => {
      try {
        const file = fileForRequest(serverRoot, req.url || '/');
        if (!file) {
          res.statusCode = 404;
          res.end('not found');
          return;
        }
        res.statusCode = 200;
        res.setHeader('Content-Type', file.mime);
        res.setHeader('Cache-Control', 'no-store');
        res.setHeader('Content-Length', file.size);
        createReadStream(file.path).pipe(res);
      } catch (error) {
        res.statusCode = 500;
        res.end(`error: ${error.message}`);
      }
    });
    server.on('error', rejectServer);
    server.listen(port, '127.0.0.1', () => {
      const address = server.address();
      resolveServer({
        server,
        url: `http://127.0.0.1:${address.port}`,
        port: address.port,
        close: () => new Promise((resolveClose) => server.close(resolveClose)),
      });
    });
  });
}
