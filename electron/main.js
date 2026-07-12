const { app, BrowserWindow, ipcMain, dialog, session } = require('electron');
const path = require('path');
const fs = require('fs');
const http = require('http');
const os = require('os');
const { execFile, spawn } = require('child_process');
const net = require('net');

// ===================== PATHS =====================
const IS_DEV = process.argv.includes('--dev');
const APP_DIR = path.join(__dirname, '..');
const USER_DATA_DIR = path.join(os.homedir(), 'VariedadesLaLomita');

// Ensure user data directory exists
if (!fs.existsSync(USER_DATA_DIR)) {
  fs.mkdirSync(USER_DATA_DIR, { recursive: true });
}

const DB_FILE = path.join(USER_DATA_DIR, 'lalomita_data.json');

// For OTA updates: if a custom index.html exists in user data, use it
function getIndexPath() {
  const customIndex = path.join(USER_DATA_DIR, 'index.html');
  if (fs.existsSync(customIndex)) {
    return customIndex;
  }
  return path.join(APP_DIR, 'index.html');
}

// ===================== ENABLE CAMERA & BARCODE DETECTOR =====================
app.commandLine.appendSwitch('enable-experimental-web-platform-features');
app.commandLine.appendSwitch('enable-features', 'ShapeDetection');
app.commandLine.appendSwitch('enable-blink-features', 'BarcodeDetector');
app.commandLine.appendSwitch('autoplay-policy', 'no-user-gesture-required');
app.commandLine.appendSwitch('unsafely-treat-insecure-origin-as-secure', 'http://localhost');

// ===================== SETUP STATUS (for AI/Ollama) =====================
let setupStatus = { step: 'idle', progress: 0.0, error: null };

function updateSetupStatus(step, progress = 0.0, error = null) {
  setupStatus = { step, progress, error };
}

function isOllamaRunning() {
  return new Promise((resolve) => {
    const req = http.request({ hostname: 'localhost', port: 11434, path: '/api/tags', method: 'GET', timeout: 2000 }, (res) => {
      resolve(res.statusCode === 200);
      res.resume();
    });
    req.on('error', () => resolve(false));
    req.on('timeout', () => { req.destroy(); resolve(false); });
    req.end();
  });
}

// ===================== DB FUNCTIONS =====================
function readDB() {
  try {
    if (fs.existsSync(DB_FILE)) {
      const data = fs.readFileSync(DB_FILE, 'utf-8');
      return data;
    }
  } catch (e) {
    console.error('Error reading DB:', e);
  }
  return '{}';
}

function writeDB(jsonStr) {
  try {
    fs.writeFileSync(DB_FILE, jsonStr, 'utf-8');
    return true;
  } catch (e) {
    console.error('Error writing DB:', e);
    return false;
  }
}

// ===================== HTTP SERVER =====================
let httpServer = null;
let serverPort = 0;

function getLocalIP() {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address;
      }
    }
  }
  return '127.0.0.1';
}

function getMimeType(ext) {
  const mimeTypes = {
    '.html': 'text/html; charset=utf-8',
    '.css': 'text/css',
    '.js': 'application/javascript',
    '.json': 'application/json',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.ico': 'image/x-icon',
    '.svg': 'image/svg+xml',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
    '.ttf': 'font/ttf',
  };
  return mimeTypes[ext] || 'application/octet-stream';
}

function fixHtml(content) {
  // Fix the stopWordsRegex pattern if malformed (same as server.py)
  const corrected = `const stopWordsRegex = /\\b(?:me|nos|te|se|le|les|yo|las|los|lo|la|compre|compro|compramos|comprados|comprado|vendo|vende|vendemos|vendio|trajo|trajeron|traer|trae|traen|llego|llegaron|ingresar|agrega|y|o|a|de|del|con|por|para|en|cada|c\\/u|unidades|uds|unds|piezas)\\b/gi;`;
  content = content.replace(
    /(?:const|var|let|)\s*stopWordsRegex\s*=\s*\/[^\n;]*;?\s*/,
    corrected
  );
  return content;
}

function collectBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', chunk => chunks.push(chunk));
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf-8')));
    req.on('error', reject);
  });
}

function sendJSON(res, statusCode, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Cache-Control': 'no-store, no-cache, must-revalidate, max-age=0',
  });
  res.end(body);
}

function sendText(res, statusCode, text, contentType = 'text/plain; charset=utf-8') {
  res.writeHead(statusCode, {
    'Content-Type': contentType,
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Cache-Control': 'no-store, no-cache, must-revalidate, max-age=0',
  });
  res.end(text);
}

async function handleRequest(req, res) {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    res.writeHead(200, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    });
    res.end();
    return;
  }

  const url = req.url.split('?')[0]; // strip query params

  // ===== GET ROUTES =====
  if (req.method === 'GET') {
    if (url === '/api/db') {
      const data = readDB();
      sendText(res, 200, data, 'application/json');
      return;
    }

    if (url === '/api/get_index') {
      try {
        const indexPath = getIndexPath();
        let content = fs.readFileSync(indexPath, 'utf-8');
        content = fixHtml(content);
        sendText(res, 200, content, 'text/plain; charset=utf-8');
      } catch (e) {
        sendText(res, 500, `Error reading index.html: ${e.message}`);
      }
      return;
    }

    if (url === '/api/info') {
      const localIp = getLocalIP();
      sendJSON(res, 200, {
        name: 'Variedades La Lomita',
        port: serverPort,
        localIp: localIp,
        syncUrl: `http://${localIp}:${serverPort}/api/db`,
        runtime: 'electron',
      });
      return;
    }

    if (url === '/api/ai/setup_status') {
      const ollamaRunning = await isOllamaRunning();
      let modelDownloaded = false;

      if (ollamaRunning) {
        try {
          modelDownloaded = await new Promise((resolve) => {
            const postData = JSON.stringify({ name: 'llama3.2' });
            const showReq = http.request({
              hostname: 'localhost', port: 11434, path: '/api/show',
              method: 'POST', headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(postData) },
              timeout: 3000,
            }, (showRes) => {
              resolve(showRes.statusCode === 200);
              showRes.resume();
            });
            showReq.on('error', () => resolve(false));
            showReq.on('timeout', () => { showReq.destroy(); resolve(false); });
            showReq.write(postData);
            showReq.end();
          });
        } catch (_) { }
      }

      const ollamaPath = path.join(os.homedir(), 'AppData', 'Local', 'Programs', 'Ollama', 'ollama.exe');
      const isInstalled = fs.existsSync(ollamaPath) || (() => {
        try {
          const result = require('child_process').execSync('where ollama', { stdio: 'pipe' });
          return result.toString().trim().length > 0;
        } catch { return false; }
      })();

      sendJSON(res, 200, {
        ...setupStatus,
        installed: isInstalled,
        running: ollamaRunning,
        model_downloaded: modelDownloaded,
      });
      return;
    }

    // ===== SERVE STATIC FILES =====
    let filePath;
    if (url === '/' || url === '' || url === '/index.html') {
      filePath = getIndexPath();
    } else {
      // Serve from APP_DIR
      const safePath = path.normalize(url).replace(/^(\.\.(\/|\\|$))+/, '');
      filePath = path.join(APP_DIR, safePath);
    }

    try {
      if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
        const ext = path.extname(filePath).toLowerCase();

        if (ext === '.html') {
          let content = fs.readFileSync(filePath, 'utf-8');
          content = fixHtml(content);
          sendText(res, 200, content, 'text/html; charset=utf-8');
        } else {
          const contentType = getMimeType(ext);
          const fileContent = fs.readFileSync(filePath);
          res.writeHead(200, {
            'Content-Type': contentType,
            'Access-Control-Allow-Origin': '*',
            'Cache-Control': 'no-store',
          });
          res.end(fileContent);
        }
      } else {
        sendText(res, 404, 'Not found');
      }
    } catch (e) {
      sendText(res, 500, `Error: ${e.message}`);
    }
    return;
  }

  // ===== POST ROUTES =====
  if (req.method === 'POST') {
    const body = await collectBody(req);

    if (url === '/api/db') {
      try {
        // Validate JSON
        JSON.parse(body);
        writeDB(body);
        sendJSON(res, 200, { status: 'success' });
      } catch (e) {
        sendJSON(res, 400, { error: e.message });
      }
      return;
    }

    if (url === '/api/update') {
      try {
        const data = JSON.parse(body);
        const code = data.code;
        if (!code) throw new Error('Falta el código de la nueva versión.');
        if (!code.toLowerCase().includes('<html') || !code.toLowerCase().includes('</html>')) {
          throw new Error('El código proporcionado no es un archivo HTML válido.');
        }

        // Write updated index.html to user data dir
        const targetFile = path.join(USER_DATA_DIR, 'index.html');
        fs.writeFileSync(targetFile, code, 'utf-8');

        sendJSON(res, 200, { status: 'success' });
      } catch (e) {
        sendJSON(res, 400, { error: e.message });
      }
      return;
    }

    if (url === '/api/ai/parse') {
      try {
        const reqData = JSON.parse(body);
        const text = reqData.text || '';
        const ollamaUrl = (reqData.ollamaUrl || 'http://localhost:11434').replace(/\/+$/, '');
        const ollamaModel = reqData.ollamaModel || 'llama3';

        const prompt = `Analiza el siguiente texto en espanol y extrae los productos, cantidades, precios de compra, precios de venta y proveedores. Responde UNICAMENTE con un objeto JSON valido con la estructura: {"items": [{"productName": "...", "quantity": 0, "purchasePrice": 0, "salePrice": 0, "supplierName": "..."}]}. Si falta algun dato, pon 0 o null segun corresponda. Texto: "${text}"`;

        const ollamaPayload = JSON.stringify({
          model: ollamaModel,
          prompt: prompt,
          stream: false,
          format: 'json',
        });

        const urlObj = new URL(`${ollamaUrl}/api/generate`);

        const ollamaRes = await new Promise((resolve, reject) => {
          const ollamaReq = http.request({
            hostname: urlObj.hostname,
            port: urlObj.port,
            path: urlObj.pathname,
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(ollamaPayload) },
            timeout: 20000,
          }, (r) => {
            const chunks = [];
            r.on('data', c => chunks.push(c));
            r.on('end', () => resolve(Buffer.concat(chunks).toString('utf-8')));
          });
          ollamaReq.on('error', reject);
          ollamaReq.on('timeout', () => { ollamaReq.destroy(); reject(new Error('Timeout')); });
          ollamaReq.write(ollamaPayload);
          ollamaReq.end();
        });

        const ollamaJson = JSON.parse(ollamaRes);
        const responseText = ollamaJson.response || '';
        const parsed = JSON.parse(responseText);
        sendJSON(res, 200, parsed);
      } catch (e) {
        sendJSON(res, 400, { error: e.message });
      }
      return;
    }

    if (url === '/api/ai/setup') {
      try {
        const data = JSON.parse(body);
        const modelName = data.model || 'llama3.2';

        if (!['idle', 'completed', 'error'].includes(setupStatus.step)) {
          sendJSON(res, 400, { error: 'Instalacion en progreso.' });
          return;
        }

        updateSetupStatus('idle', 0.0);

        // Run setup in background
        runOllamaSetup(modelName).catch(e => {
          console.error('Ollama setup error:', e);
          updateSetupStatus('error', 0, e.message);
        });

        sendJSON(res, 200, { status: 'started' });
      } catch (e) {
        sendJSON(res, 400, { error: e.message });
      }
      return;
    }

    sendJSON(res, 404, { error: 'Not found' });
    return;
  }

  sendText(res, 405, 'Method not allowed');
}

// ===================== OLLAMA SETUP =====================
async function runOllamaSetup(modelName) {
  const ollamaPath = path.join(os.homedir(), 'AppData', 'Local', 'Programs', 'Ollama', 'ollama.exe');

  let isInstalled = fs.existsSync(ollamaPath);
  if (!isInstalled) {
    try {
      require('child_process').execSync('where ollama', { stdio: 'pipe' });
      isInstalled = true;
    } catch { }
  }

  if (!isInstalled) {
    updateSetupStatus('downloading_ollama', 0.0);
    const https = require('https');
    const tmpDir = os.tmpdir();
    const installerPath = path.join(tmpDir, 'OllamaSetup.exe');

    await new Promise((resolve, reject) => {
      const downloadUrl = 'https://ollama.com/download/OllamaSetup.exe';
      const makeRequest = (url) => {
        const proto = url.startsWith('https') ? https : http;
        proto.get(url, { headers: { 'User-Agent': 'Mozilla/5.0' } }, (response) => {
          if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
            makeRequest(response.headers.location);
            return;
          }
          const totalSize = parseInt(response.headers['content-length'] || '0', 10);
          let downloaded = 0;
          const file = fs.createWriteStream(installerPath);
          response.on('data', (chunk) => {
            downloaded += chunk.length;
            file.write(chunk);
            if (totalSize > 0) {
              updateSetupStatus('downloading_ollama', Math.round((downloaded / totalSize) * 100 * 10) / 10);
            }
          });
          response.on('end', () => { file.end(); resolve(); });
          response.on('error', reject);
        }).on('error', reject);
      };
      makeRequest(downloadUrl);
    });

    updateSetupStatus('installing_ollama', 100.0);
    try {
      await new Promise((resolve, reject) => {
        execFile(installerPath, ['/silent'], (err) => {
          if (err) reject(err); else resolve();
        });
      });
    } catch (e) {
      updateSetupStatus('error', 0, `Error al ejecutar instalador: ${e.message}`);
      return;
    }

    try { fs.unlinkSync(installerPath); } catch { }
  }

  // Check if running
  const running = await isOllamaRunning();
  if (!running) {
    updateSetupStatus('starting_ollama', 0.0);
    const executable = fs.existsSync(ollamaPath) ? ollamaPath : 'ollama';
    try {
      spawn(executable, ['serve'], { detached: true, stdio: 'ignore', windowsHide: true }).unref();
    } catch { }

    let started = false;
    for (let i = 0; i < 15; i++) {
      if (await isOllamaRunning()) { started = true; break; }
      await new Promise(r => setTimeout(r, 1000));
    }
    if (!started) {
      updateSetupStatus('error', 0, 'El servicio de Ollama no pudo iniciarse de forma automática.');
      return;
    }
  }

  // Pull model
  updateSetupStatus('pulling_model', 0.0);

  // Check if model exists
  let modelExists = false;
  try {
    modelExists = await new Promise((resolve) => {
      const postData = JSON.stringify({ name: modelName });
      const showReq = http.request({
        hostname: 'localhost', port: 11434, path: '/api/show',
        method: 'POST', headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(postData) },
        timeout: 3000,
      }, (r) => { resolve(r.statusCode === 200); r.resume(); });
      showReq.on('error', () => resolve(false));
      showReq.write(postData);
      showReq.end();
    });
  } catch { }

  if (!modelExists) {
    try {
      const pullPayload = JSON.stringify({ name: modelName, stream: true });
      await new Promise((resolve, reject) => {
        const pullReq = http.request({
          hostname: 'localhost', port: 11434, path: '/api/pull',
          method: 'POST', headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(pullPayload) },
        }, (r) => {
          r.on('data', (chunk) => {
            const lines = chunk.toString().split('\n').filter(l => l.trim());
            for (const line of lines) {
              try {
                const statusData = JSON.parse(line);
                const total = statusData.total || 0;
                const completed = statusData.completed || 0;
                if (total > 0) {
                  updateSetupStatus('pulling_model', Math.round((completed / total) * 100 * 10) / 10);
                }
              } catch { }
            }
          });
          r.on('end', resolve);
          r.on('error', reject);
        });
        pullReq.on('error', reject);
        pullReq.write(pullPayload);
        pullReq.end();
      });
    } catch (e) {
      updateSetupStatus('error', 0, `Error al descargar el modelo ${modelName}: ${e.message}`);
      return;
    }
  }

  updateSetupStatus('completed', 100.0);
}

// ===================== FIND FREE PORT =====================
function findFreePort(startPort) {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.on('error', () => {
      resolve(findFreePort(startPort + 1));
    });
    server.listen(startPort, () => {
      const port = server.address().port;
      server.close(() => resolve(port));
    });
  });
}

// ===================== START SERVER & WINDOW =====================
let mainWindow = null;

function createWindow() {
  // Resolve icon path
  const iconPath = path.join(APP_DIR, 'logo.ico');

  mainWindow = new BrowserWindow({
    width: 1400,
    height: 900,
    minWidth: 900,
    minHeight: 600,
    icon: iconPath,
    title: 'Variedades La Lomita',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      webSecurity: true,
    },
    show: false,
    autoHideMenuBar: true,
  });

  mainWindow.setMenuBarVisibility(false);

  // Load via HTTP server (same approach as pywebview/server.py)
  mainWindow.loadURL(`http://localhost:${serverPort}`);

  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
  });

  if (IS_DEV) {
    mainWindow.webContents.openDevTools();
  }

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

// ===================== IPC HANDLERS (legacy preload support) =====================
ipcMain.handle('save-file', async (event, filePath, content) => {
  try {
    fs.writeFileSync(filePath, content, 'utf-8');
    return { success: true };
  } catch (e) {
    return { success: false, error: e.message };
  }
});

ipcMain.handle('read-file', async (event, filePath) => {
  try {
    const content = fs.readFileSync(filePath, 'utf-8');
    return { success: true, content };
  } catch (e) {
    return { success: false, error: e.message };
  }
});

ipcMain.handle('get-app-path', async () => {
  return getIndexPath();
});

ipcMain.handle('reload-app', async () => {
  if (mainWindow) {
    mainWindow.reload();
  }
  return true;
});

ipcMain.handle('get-app-version', async () => {
  return '1.27.0';
});

ipcMain.handle('show-confirm', async (event, message) => {
  const result = await dialog.showMessageBox(mainWindow, {
    type: 'question',
    buttons: ['Cancelar', 'Aceptar'],
    defaultId: 1,
    title: 'Confirmar',
    message: message,
  });
  return result.response === 1;
});

// ===================== APP LIFECYCLE =====================
app.whenReady().then(async () => {
  // Grant camera permissions automatically
  session.defaultSession.setPermissionRequestHandler((webContents, permission, callback, details) => {
    const allowedPermissions = ['media', 'mediaKeySystem', 'clipboard-read', 'clipboard-sanitized-write', 'videoCapture', 'audioCapture'];
    if (allowedPermissions.includes(permission)) {
      callback(true);
    } else {
      callback(false);
    }
  });

  // Also handle permission checks
  session.defaultSession.setPermissionCheckHandler((webContents, permission) => {
    const allowedPermissions = ['media', 'mediaKeySystem', 'clipboard-read', 'clipboard-sanitized-write', 'videoCapture', 'audioCapture'];
    return allowedPermissions.includes(permission);
  });

  // Find a free port
  serverPort = await findFreePort(5000);
  console.log(`Starting HTTP server on port ${serverPort}...`);

  // Create HTTP server
  httpServer = http.createServer(async (req, res) => {
    try {
      await handleRequest(req, res);
    } catch (e) {
      console.error('Server error:', e);
      try {
        sendText(res, 500, `Internal server error: ${e.message}`);
      } catch { }
    }
  });

  httpServer.listen(serverPort, '127.0.0.1', () => {
    console.log(`HTTP server running at http://localhost:${serverPort}`);
    createWindow();
  });

  httpServer.on('error', (e) => {
    console.error('HTTP server error:', e);
    dialog.showErrorBox('Error del Servidor', `No se pudo iniciar el servidor local: ${e.message}`);
    app.quit();
  });
});

app.on('window-all-closed', () => {
  if (httpServer) {
    httpServer.close();
  }
  app.quit();
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createWindow();
  }
});
