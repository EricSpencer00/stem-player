const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('stemacleNative', {
  platform: process.platform,
  getDesktopState: () => ipcRenderer.invoke('stemacle:get-desktop-state'),
  pickAudioFiles: () => ipcRenderer.invoke('stemacle:pick-audio-files'),
  pickAudioFolder: () => ipcRenderer.invoke('stemacle:pick-audio-folder'),
  addLibraryPaths: (paths) => ipcRenderer.invoke('stemacle:add-library-paths', paths),
  rescanLibrary: () => ipcRenderer.invoke('stemacle:rescan-library'),
  enqueueAnalysis: (trackId, options) => ipcRenderer.invoke('stemacle:enqueue-analysis', trackId, options),
  enqueueDownload: (url) => ipcRenderer.invoke('stemacle:enqueue-download', url),
  saveSession: (session) => ipcRenderer.invoke('stemacle:save-session', session),
  exportTrack: (trackId, options) => ipcRenderer.invoke('stemacle:export-track', trackId, options),
  readTrackFile: (trackId) => ipcRenderer.invoke('stemacle:read-track-file', trackId),
  revealPath: (filePath) => ipcRenderer.invoke('stemacle:reveal-path', filePath),
  clearDesktopState: () => ipcRenderer.invoke('stemacle:clear-desktop-state'),
  onStateChanged: (handler) => {
    const listener = (_event, state) => handler(state);
    ipcRenderer.on('stemacle:desktop-state', listener);
    return () => ipcRenderer.removeListener('stemacle:desktop-state', listener);
  },
  onCommand: (handler) => {
    ipcRenderer.on('stemacle:command', (_event, command) => handler(command));
  },
});
