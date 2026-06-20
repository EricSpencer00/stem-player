const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('stemacleNative', {
  platform: process.platform,
  getDesktopState: () => ipcRenderer.invoke('stemacle:get-desktop-state'),
  pickAudioFiles: () => ipcRenderer.invoke('stemacle:pick-audio-files'),
  pickAudioFolder: () => ipcRenderer.invoke('stemacle:pick-audio-folder'),
  addLibraryPaths: (paths) => ipcRenderer.invoke('stemacle:add-library-paths', paths),
  enqueueAnalysis: (trackId, options) => ipcRenderer.invoke('stemacle:enqueue-analysis', trackId, options),
  saveSession: (session) => ipcRenderer.invoke('stemacle:save-session', session),
  exportTrack: (trackId, options) => ipcRenderer.invoke('stemacle:export-track', trackId, options),
  revealPath: (filePath) => ipcRenderer.invoke('stemacle:reveal-path', filePath),
  clearDesktopState: () => ipcRenderer.invoke('stemacle:clear-desktop-state'),
  onCommand: (handler) => {
    ipcRenderer.on('stemacle:command', (_event, command) => handler(command));
  },
});
