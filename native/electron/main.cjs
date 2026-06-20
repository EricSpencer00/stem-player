const { app, BrowserWindow, dialog, ipcMain, Menu, net, Notification, protocol, shell } = require('electron');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { createDesktopStore } = require('./stemacle-desktop.cjs');

const appRoot = path.resolve(__dirname, '..', '..');
const distRoot = path.join(appRoot, 'dist', 'native');
const sourceRoot = appRoot;
const scheme = 'stemacle';
let mainWindow = null;
let desktopStore = null;

protocol.registerSchemesAsPrivileged([
  {
    scheme,
    privileges: {
      standard: true,
      secure: true,
      supportFetchAPI: true,
      corsEnabled: true,
      stream: true,
    },
  },
]);

function bundleRoot() {
  return fs.existsSync(path.join(distRoot, 'index.html')) ? distRoot : sourceRoot;
}

function pathInside(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative && !relative.startsWith('..') && !path.isAbsolute(relative);
}

function nativeRelativePath(urlPath, root) {
  let pathname = decodeURIComponent(urlPath || '/');
  if (pathname.endsWith('/')) pathname += 'index.html';
  if (pathname === '/index.html' && root === sourceRoot) return path.join('native', 'index.html');
  return pathname.replace(/^\/+/, '');
}

function fileForRequest(requestUrl) {
  const url = new URL(requestUrl);
  const root = bundleRoot();
  const relativePath = nativeRelativePath(url.pathname, root);
  let candidate = path.normalize(path.join(root, relativePath));

  if (!pathInside(root, candidate)) {
    return null;
  }

  if (fs.existsSync(candidate) && fs.statSync(candidate).isDirectory()) {
    candidate = path.join(candidate, 'index.html');
  }

  return candidate;
}

function createWindow() {
  const win = new BrowserWindow({
    width: 1240,
    height: 880,
    minWidth: 920,
    minHeight: 720,
    title: 'Stemacle',
    backgroundColor: '#e8dfcf',
    icon: path.join(appRoot, 'native', 'electron', 'icon.png'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });

  mainWindow = win;
  win.loadURL(`${scheme}://app/`);

  win.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith(`${scheme}://app`)) return { action: 'allow' };
    shell.openExternal(url);
    return { action: 'deny' };
  });

  win.webContents.on('will-navigate', (event, url) => {
    if (url.startsWith(`${scheme}://app`)) return;
    event.preventDefault();
    shell.openExternal(url);
  });
}

function sendCommand(command) {
  const win = BrowserWindow.getFocusedWindow() || mainWindow;
  win?.webContents.send('stemacle:command', command);
}

function installMenu() {
  const template = [
    {
      label: 'Stemacle',
      submenu: [
        { role: 'about' },
        { type: 'separator' },
        {
          label: 'Command Palette',
          accelerator: 'CommandOrControl+K',
          click: () => sendCommand('command-palette'),
        },
        {
          label: 'Add Audio Files',
          accelerator: 'CommandOrControl+O',
          click: () => sendCommand('add-audio-files'),
        },
        {
          label: 'Add Folder',
          accelerator: 'CommandOrControl+Shift+O',
          click: () => sendCommand('add-audio-folder'),
        },
        { type: 'separator' },
        { role: 'quit' },
      ],
    },
    {
      label: 'Library',
      submenu: [
        {
          label: 'Run High Quality Analysis',
          accelerator: 'CommandOrControl+R',
          click: () => sendCommand('reanalyze-selected'),
        },
        {
          label: 'Export Stem Pack',
          accelerator: 'CommandOrControl+E',
          click: () => sendCommand('export-selected'),
        },
        {
          label: 'Save Session',
          accelerator: 'CommandOrControl+S',
          click: () => sendCommand('save-session'),
        },
      ],
    },
    {
      label: 'View',
      submenu: [
        { role: 'reload' },
        { role: 'toggleDevTools' },
        { type: 'separator' },
        { role: 'resetZoom' },
        { role: 'zoomIn' },
        { role: 'zoomOut' },
      ],
    },
  ];

  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

async function chooseAudioFiles(properties) {
  const result = await dialog.showOpenDialog({
    title: properties.includes('openDirectory') ? 'Add Stemacle Music Folder' : 'Add audio to Stemacle Library',
    properties,
    filters: [
      {
        name: 'Audio',
        extensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'opus', 'aiff', 'aif'],
      },
    ],
  });

  if (result.canceled) return [];
  return desktopStore.addLibraryPaths(result.filePaths);
}

app.whenReady().then(() => {
  desktopStore = createDesktopStore(path.join(app.getPath('userData'), 'Stemacle Desktop'));

  protocol.handle(scheme, (request) => {
    const filePath = fileForRequest(request.url);
    if (!filePath || !fs.existsSync(filePath)) {
      return new Response('Not found', { status: 404 });
    }

    return net.fetch(pathToFileURL(filePath).toString());
  });

  ipcMain.handle('stemacle:get-desktop-state', () => desktopStore.getState());
  ipcMain.handle('stemacle:pick-audio-files', () => chooseAudioFiles(['openFile', 'multiSelections']));
  ipcMain.handle('stemacle:pick-audio-folder', () => chooseAudioFiles(['openDirectory', 'multiSelections']));
  ipcMain.handle('stemacle:add-library-paths', (_event, paths) => desktopStore.addLibraryPaths(Array.isArray(paths) ? paths : []));
  ipcMain.handle('stemacle:enqueue-analysis', (_event, trackId, options) => {
    const job = desktopStore.enqueueAnalysis(trackId, options || {});
    if (Notification.isSupported()) {
      new Notification({
        title: 'Stemacle analysis queued',
        body: `${job.trackName} · ${job.quality}`,
      }).show();
    }
    return job;
  });
  ipcMain.handle('stemacle:save-session', (_event, session) => desktopStore.saveSession(session || {}));
  ipcMain.handle('stemacle:export-track', (_event, trackId, options) => desktopStore.planExport(trackId, options || {}));
  ipcMain.handle('stemacle:reveal-path', (_event, filePath) => {
    if (filePath && fs.existsSync(filePath)) {
      shell.showItemInFolder(filePath);
      return true;
    }
    return false;
  });
  ipcMain.handle('stemacle:clear-desktop-state', () => {
    const state = desktopStore.clear();
    return state;
  });

  installMenu();
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
