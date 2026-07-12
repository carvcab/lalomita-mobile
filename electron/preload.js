const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  saveFile: (filePath, content) => ipcRenderer.invoke('save-file', filePath, content),
  readFile: (filePath) => ipcRenderer.invoke('read-file', filePath),
  getAppPath: () => ipcRenderer.invoke('get-app-path'),
  showConfirm: (message) => ipcRenderer.invoke('show-confirm', message),
  reloadApp: () => ipcRenderer.invoke('reload-app'),
  getAppVersion: () => ipcRenderer.invoke('get-app-version'),
  isElectron: true,
  platform: process.platform,
  versions: {
    electron: process.versions.electron,
    chrome: process.versions.chrome,
    node: process.versions.node,
  }
});
