import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize, relative, resolve } from 'node:path';

const root = resolve(process.cwd(), 'dist/native');
const requestedPort = Number(process.env.STEMACLE_PORT || process.env.PORT || 4177);
const hasFixedPort = Boolean(process.env.STEMACLE_PORT || process.env.PORT);
const host = process.env.STEMACLE_HOST || process.env.HOST || '127.0.0.1';

function normalizePort(value) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 && parsed < 65536 ? parsed : 4177;
}

const port = normalizePort(requestedPort);

const mimeTypes = {
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
};

function fileForRequest(url) {
  const requestUrl = new URL(url, `http://127.0.0.1:${port}`);
  let pathname = decodeURIComponent(requestUrl.pathname);
  if (pathname === '/') pathname = '/index.html';
  if (pathname.endsWith('/')) pathname += 'index.html';

  const candidate = normalize(join(root, pathname));
  const rel = relative(root, candidate);
  if (rel.startsWith('..') || rel.includes(`..${process.platform === 'win32' ? '\\' : '/'}`)) {
    return null;
  }
  return candidate;
}

if (!existsSync(root)) {
  throw new Error('dist/native is missing. Run npm run native:prepare first.');
}

async function startServer() {
  for (let attempt = 0; attempt <= 20; attempt += 1) {
    const currentPort = port + attempt;
    const server = createServer((request, response) => {
      const filePath = fileForRequest(request.url || '/');
      if (!filePath || !existsSync(filePath) || !statSync(filePath).isFile()) {
        response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
        response.end('Not found');
        return;
      }

      response.writeHead(200, {
        'content-type': mimeTypes[extname(filePath)] || 'application/octet-stream',
        'cache-control': 'no-store',
      });
      createReadStream(filePath).pipe(response);
    });

    const boundPort = await new Promise((resolve, reject) => {
      const onError = (error) => {
        if (!hasFixedPort && error.code === 'EADDRINUSE') {
          resolve(null);
          return;
        }
        reject(error);
      };

      server.once('error', onError);
      server.listen(currentPort, host, () => {
        server.removeListener('error', onError);
        resolve(currentPort);
      });
    });

    if (boundPort === null) {
      continue;
    }

    const displayHost = host === '0.0.0.0' ? 'localhost' : host;
    console.log(`Stemacle web workbench demo: http://${displayHost}:${boundPort}/`);
    return;
  }

  throw new Error(`No free port found in range ${port}..${port + 20} on ${host}.`);
}

startServer();
  });
  createReadStream(filePath).pipe(response);
});

server.listen(port, '127.0.0.1', () => {
  console.log(`Stemacle web workbench demo: http://127.0.0.1:${port}/`);
});
