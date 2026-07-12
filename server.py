# [ignoring loop detection]
import http.server
import socketserver
import json
import os
import sqlite3

import sys
import threading
import webview
import time
import subprocess
import shutil
import tempfile

PORT = 5000

# Determine directory paths for running frozen (.exe) vs unfrozen (.py)
if getattr(sys, 'frozen', False):
    BASE_DIR = sys._MEIPASS
    # Store database in user's profile directory under a custom folder
    DB_DIR = os.path.join(os.path.expanduser('~'), 'VariedadesLaLomita')
    os.makedirs(DB_DIR, exist_ok=True)
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))
    DB_DIR = BASE_DIR

DB_FILE = os.path.join(DB_DIR, 'lalomita.db')

setup_status = {"step": "idle", "progress": 0.0, "error": None}

def update_status(step, progress=0.0, error=None):
    global setup_status
    setup_status["step"] = step
    setup_status["progress"] = progress
    setup_status["error"] = error

def is_ollama_running():
    import urllib.request
    try:
        with urllib.request.urlopen("http://localhost:11434/api/tags", timeout=2) as response:
            return response.status == 200
    except:
        return False

def run_ollama_setup_thread(model_name):
    import urllib.request
    import urllib.error
    
    user_profile = os.path.expanduser('~')
    ollama_path = os.path.join(user_profile, 'AppData', 'Local', 'Programs', 'Ollama', 'ollama.exe')
    
    # 1. Detect if installed
    is_installed = (shutil.which("ollama") is not None) or os.path.exists(ollama_path)
    
    if not is_installed:
        update_status("downloading_ollama", 0.0)
        url = "https://ollama.com/download/OllamaSetup.exe"
        temp_dir = tempfile.gettempdir()
        installer_path = os.path.join(temp_dir, "OllamaSetup.exe")
        
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req) as response:
                total_size = int(response.headers.get('content-length', 0))
                downloaded = 0
                block_size = 1024 * 1024
                with open(installer_path, 'wb') as f:
                    while True:
                        buffer = response.read(block_size)
                        if not buffer:
                            break
                        downloaded += len(buffer)
                        f.write(buffer)
                        if total_size > 0:
                            progress = round((downloaded / total_size) * 100, 1)
                            update_status("downloading_ollama", progress)
        except Exception as e:
            update_status("error", error=f"Error al descargar instalador: {str(e)}")
            return
            
        update_status("installing_ollama", 100.0)
        try:
            subprocess.run([installer_path, "/silent"], check=True)
        except Exception as e:
            update_status("error", error=f"Error al ejecutar instalador: {str(e)}")
            return
            
        try:
            os.remove(installer_path)
        except:
            pass
            
    # 2. Check if running
    if not is_ollama_running():
        update_status("starting_ollama", 0.0)
        executable = "ollama"
        if not shutil.which("ollama"):
            executable = ollama_path
            
        try:
            subprocess.Popen([executable, "serve"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0)
        except Exception as e:
            pass
            
        started = False
        for _ in range(15):
            if is_ollama_running():
                started = True
                break
            time.sleep(1)
            
        if not started:
            update_status("error", error="El servicio de Ollama no pudo iniciarse de forma automática. Por favor ejecútalo manualmente.")
            return
            
    # 3. Pull model
    update_status("pulling_model", 0.0)
    model_exists = False
    try:
        show_req = urllib.request.Request(
            "http://localhost:11434/api/show",
            data=json.dumps({"name": model_name}).encode('utf-8'),
            headers={'Content-Type': 'application/json'}
        )
        with urllib.request.urlopen(show_req, timeout=3) as show_res:
            if show_res.status == 200:
                model_exists = True
    except:
        pass
        
    if not model_exists:
        try:
            pull_url = "http://localhost:11434/api/pull"
            pull_payload = {"name": model_name, "stream": True}
            req = urllib.request.Request(
                pull_url,
                data=json.dumps(pull_payload).encode('utf-8'),
                headers={'Content-Type': 'application/json'}
            )
            with urllib.request.urlopen(req) as response:
                for line in response:
                    if not line.strip():
                        continue
                    try:
                        status_data = json.loads(line.decode('utf-8'))
                        total = status_data.get("total", 0)
                        completed = status_data.get("completed", 0)
                        if total > 0:
                            progress = round((completed / total) * 100, 1)
                            update_status("pulling_model", progress)
                        else:
                            update_status("pulling_model", 0.0)
                    except:
                        pass
        except Exception as e:
            update_status("error", error=f"Error al descargar el modelo {model_name}: {str(e)}")
            return
            
    update_status("completed", 100.0)

def init_sqlite_db():
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute('''
        CREATE TABLE IF NOT EXISTS app_state (
            key TEXT PRIMARY KEY,
            val TEXT
        )
    ''')
    c.execute('''
        CREATE TABLE IF NOT EXISTS products (
            id TEXT PRIMARY KEY,
            name TEXT,
            category TEXT,
            active INTEGER,
            buyPrice REAL,
            sellPrice REAL,
            barcode TEXT
        )
    ''')
    try:
        c.execute("ALTER TABLE products ADD COLUMN barcode TEXT")
    except sqlite3.OperationalError:
        pass
    c.execute('''
        CREATE TABLE IF NOT EXISTS sales (
            id TEXT PRIMARY KEY,
            date TEXT,
            total REAL,
            paymentMethod TEXT,
            customerName TEXT,
            notes TEXT
        )
    ''')
    c.execute('''
        CREATE TABLE IF NOT EXISTS fiados_pagos (
            id TEXT PRIMARY KEY,
            saleId TEXT,
            customerName TEXT,
            amount REAL,
            payMethod TEXT,
            date TEXT,
            createdAt TEXT
        )
    ''')
    c.execute('''
        CREATE TABLE IF NOT EXISTS clientDetails (
            name TEXT PRIMARY KEY,
            phone TEXT,
            creditLimit REAL
        )
    ''')
    c.execute('''
        CREATE TABLE IF NOT EXISTS copy_prices (
            paperType TEXT,
            serviceType TEXT,
            price REAL,
            PRIMARY KEY (paperType, serviceType)
        )
    ''')
    c.execute('''
        CREATE TABLE IF NOT EXISTS copy_paper_stock (
            paperType TEXT PRIMARY KEY,
            stock INTEGER
        )
    ''')
    c.execute('''
        CREATE TABLE IF NOT EXISTS copy_ream_stock (
            paperType TEXT PRIMARY KEY,
            stock INTEGER,
            cost REAL
        )
    ''')
    c.execute('''
        CREATE TABLE IF NOT EXISTS copy_expenses (
            id TEXT PRIMARY KEY,
            date TEXT,
            type TEXT,
            description TEXT,
            amount REAL,
            createdAt TEXT
        )
    ''')
    c.execute('''
        CREATE TABLE IF NOT EXISTS copy_paper_types (
            id TEXT PRIMARY KEY,
            name TEXT,
            weight TEXT,
            active INTEGER
        )
    ''')
    conn.commit()
    conn.close()

def sync_relational_tables(data_str):
    try:
        data = json.loads(data_str)
    except Exception as e:
        print("Error parsing JSON for relational sync:", e)
        return

    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()

    c.execute("DELETE FROM products")
    c.execute("DELETE FROM sales")
    c.execute("DELETE FROM fiados_pagos")
    c.execute("DELETE FROM clientDetails")
    c.execute("DELETE FROM copy_prices")
    c.execute("DELETE FROM copy_paper_stock")
    c.execute("DELETE FROM copy_ream_stock")
    c.execute("DELETE FROM copy_expenses")
    c.execute("DELETE FROM copy_paper_types")

    prod_suppliers = data.get('prodSuppliers', [])
    for p in data.get('products', []):
        p_id = p.get('id')
        links = [x for x in prod_suppliers if x.get('productId') == p_id]
        def_link = next((x for x in links if x.get('isDefault')), None) or (links[0] if links else {})
        buy_p = float(def_link.get('purchasePrice') or 0)
        sell_p = float(def_link.get('salePrice') or 0)
        c.execute(
            "INSERT INTO products (id, name, category, active, buyPrice, sellPrice, barcode) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (p_id, p.get('name'), p.get('category'), 1 if p.get('active', True) else 0, buy_p, sell_p, p.get('barcode'))
        )

    for s in data.get('sales', []):
        c.execute(
            "INSERT INTO sales (id, date, total, paymentMethod, customerName, notes) VALUES (?, ?, ?, ?, ?, ?)",
            (s.get('id'), s.get('date'), float(s.get('total') or 0), s.get('paymentMethod'), s.get('customerName'), s.get('notes'))
        )

    for p in data.get('fiados_pagos', []):
        c.execute(
            "INSERT INTO fiados_pagos (id, saleId, customerName, amount, payMethod, date, createdAt) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (p.get('id'), p.get('saleId'), p.get('customerName'), float(p.get('amount') or 0), p.get('payMethod'), p.get('date'), p.get('createdAt'))
        )

    clients = data.get('clientDetails', {})
    for name, details in clients.items():
        if not details: continue
        c.execute(
            "INSERT INTO clientDetails (name, phone, creditLimit) VALUES (?, ?, ?)",
            (name, details.get('phone'), float(details.get('limit') or 0))
        )

    for ct in data.get('copyPaperTypes', []):
        c.execute(
            "INSERT INTO copy_paper_types (id, name, weight, active) VALUES (?, ?, ?, ?)",
            (ct.get('id'), ct.get('name'), ct.get('weight'), 1 if ct.get('active', True) else 0)
        )

    for ce in data.get('copyExpenses', []):
        c.execute(
            "INSERT INTO copy_expenses (id, date, type, description, amount, createdAt) VALUES (?, ?, ?, ?, ?, ?)",
            (ce.get('id'), ce.get('date'), ce.get('type'), ce.get('description'), float(ce.get('amount') or 0), ce.get('createdAt'))
        )

    copyPrices = data.get('copyPrices', {})
    for paperType, services in copyPrices.items():
        if isinstance(services, dict):
            for serviceType, price in services.items():
                c.execute(
                    "INSERT INTO copy_prices (paperType, serviceType, price) VALUES (?, ?, ?)",
                    (paperType, serviceType, float(price or 0))
                )

    copyPaperStock = data.get('copyPaperStock', {})
    for paperType, stock in copyPaperStock.items():
        c.execute(
            "INSERT INTO copy_paper_stock (paperType, stock) VALUES (?, ?)",
            (paperType, int(stock or 0))
        )

    copyReamStock = data.get('copyReamStock', {})
    for paperType, stock in copyReamStock.items():
        cost = stock.get('cost', 0) if isinstance(stock, dict) else 0
        qty = stock.get('qty', stock) if isinstance(stock, dict) else stock
        c.execute(
            "INSERT INTO copy_ream_stock (paperType, stock, cost) VALUES (?, ?, ?)",
            (paperType, int(qty or 0), float(cost or 0))
        )

    conn.commit()
    conn.close()

class POSRequestHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200, "ok")
        self.end_headers()

    @staticmethod
    def fix_html(content):
        import re
        corrected = r"const stopWordsRegex = /\b(?:me|nos|te|se|le|les|yo|las|los|lo|la|compre|compro|compramos|comprados|comprado|vendo|vende|vendemos|vendio|trajo|trajeron|traer|trae|traen|llego|llegaron|ingresar|agrega|y|o|a|de|del|con|por|para|en|cada|c\/u|unidades|uds|unds|piezas)\b/gi;"
        content = re.sub(
            r'(?:const|var|let|)\s*stopWordsRegex\s*=\s*/[^\n;]*;?\s*',
            corrected,
            content
        )
        return content

    def translate_path(self, path):
        default_path = super().translate_path(path)
        filename = os.path.basename(default_path)
        if filename == 'index.html' and getattr(sys, 'frozen', False):
            custom_path = os.path.join(DB_DIR, 'index.html')
            if os.path.exists(custom_path):
                return custom_path
        return default_path

    def do_GET(self):
        if self.path == '/api/db':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            conn = sqlite3.connect(DB_FILE)
            c = conn.cursor()
            c.execute("SELECT val FROM app_state WHERE key = 'pos_data'")
            row = c.fetchone()
            conn.close()
            if row:
                self.wfile.write(row[0].encode('utf-8'))
            else:
                self.wfile.write(b'{}')
        elif self.path == '/api/get_index':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain; charset=utf-8')
            self.end_headers()
            if getattr(sys, 'frozen', False):
                custom_path = os.path.join(DB_DIR, 'index.html')
                if os.path.exists(custom_path):
                    target_file = custom_path
                else:
                    target_file = os.path.join(BASE_DIR, 'index.html')
            else:
                target_file = os.path.join(BASE_DIR, 'index.html')
            try:
                with open(target_file, 'r', encoding='utf-8') as f:
                    content = f.read()
                content = self.fix_html(content)
                self.wfile.write(content.encode('utf-8'))
            except Exception as e:
                self.wfile.write(f"Error reading local file: {str(e)}".encode('utf-8'))
        elif self.path == '/api/info':
            import socket
            hostname = socket.gethostname()
            local_ip = '127.0.0.1'
            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                s.connect(('8.8.8.8', 80))
                local_ip = s.getsockname()[0]
                s.close()
            except Exception:
                pass
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            info = {
                'name': 'Variedades La Lomita',
                'port': PORT,
                'localIp': local_ip,
                'syncUrl': f'http://{local_ip}:{PORT}/api/db'
            }
            self.wfile.write(json.dumps(info).encode('utf-8'))
        elif self.path == '/api/ai/setup_status':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()

            is_installed = (shutil.which("ollama") is not None) or os.path.exists(os.path.join(os.path.expanduser('~'), 'AppData', 'Local', 'Programs', 'Ollama', 'ollama.exe'))
            is_running = is_ollama_running()
            model_downloaded = False
            if is_running:
                try:
                    import urllib.request
                    show_req = urllib.request.Request(
                        "http://localhost:11434/api/show",
                        data=json.dumps({"name": "llama3.2"}).encode('utf-8'),
                        headers={'Content-Type': 'application/json'}
                    )
                    with urllib.request.urlopen(show_req, timeout=3) as show_res:
                        if show_res.status == 200:
                            model_downloaded = True
                except:
                    pass

            response_data = dict(setup_status)
            response_data["installed"] = is_installed
            response_data["running"] = is_running
            response_data["model_downloaded"] = model_downloaded
            self.wfile.write(json.dumps(response_data).encode('utf-8'))
        else:
            if self.path == '/' or self.path == '':
                self.path = '/index.html'
            if self.path == '/index.html':
                import io
                self.send_response(200)
                self.send_header('Content-type', 'text/html; charset=utf-8')
                self.end_headers()
                target = self.translate_path(self.path)
                try:
                    with open(target, 'r', encoding='utf-8') as f:
                        content = f.read()
                    content = self.fix_html(content)
                    self.wfile.write(content.encode('utf-8'))
                except Exception as e:
                    self.wfile.write(f"Error: {e}".encode('utf-8'))
            else:
                super().do_GET()

    def do_POST(self):
        if self.path == '/api/db':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            try:
                data_str = post_data.decode('utf-8')
                json.loads(data_str)
                
                conn = sqlite3.connect(DB_FILE)
                c = conn.cursor()
                c.execute("INSERT OR REPLACE INTO app_state (key, val) VALUES ('pos_data', ?)", (data_str,))
                conn.commit()
                conn.close()

                sync_relational_tables(data_str)

                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"status":"success"}')
            except Exception as e:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(f'{{"error":"{str(e)}"}}'.encode('utf-8'))
        elif self.path == '/api/update':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            try:
                data = json.loads(post_data.decode('utf-8'))
                code = data.get('code')
                if not code:
                    raise Exception("Falta el código de la nueva versión.")
                
                if '<html' not in code.lower() or '</html>' not in code.lower():
                    raise Exception("El código proporcionado no es un archivo HTML válido.")
                
                if getattr(sys, 'frozen', False):
                    target_file = os.path.join(DB_DIR, 'index.html')
                else:
                    target_file = os.path.join(BASE_DIR, 'index.html')
                
                with open(target_file, 'w', encoding='utf-8') as f:
                    f.write(code)
                
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"status":"success"}')
            except Exception as e:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(f'{{"error":"{str(e)}"}}'.encode('utf-8'))
        elif self.path == '/api/ai/parse':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            try:
                import urllib.request
                import urllib.error
                
                req_data = json.loads(post_data.decode('utf-8'))
                text = req_data.get('text', '')
                provider = req_data.get('provider', 'ollama')
                ollama_url = req_data.get('ollamaUrl', 'http://localhost:11434').rstrip('/')
                ollama_model = req_data.get('ollamaModel', 'llama3')
                
                prompt = (
                    "Analiza el siguiente texto en espanol y extrae los productos, cantidades, precios de compra, "
                    "precios de venta y proveedores. Responde UNICAMENTE con un objeto JSON valido con la estructura: "
                    "{\"items\": [{\"productName\": \"...\", \"quantity\": 0, \"purchasePrice\": 0, \"salePrice\": 0, \"supplierName\": \"...\"}]}. "
                    "Si falta algun dato, pon 0 o null segun corresponda. Texto: "
                    f"\"{text}\""
                )
                
                if provider == 'ollama':
                    ollama_payload = {
                        "model": ollama_model,
                        "prompt": prompt,
                        "stream": False,
                        "format": "json"
                    }
                    
                    req_url = f"{ollama_url}/api/generate"
                    req = urllib.request.Request(
                        req_url,
                        data=json.dumps(ollama_payload).encode('utf-8'),
                        headers={'Content-Type': 'application/json'}
                    )
                    
                    try:
                        with urllib.request.urlopen(req, timeout=20) as response:
                            resp_data = response.read().decode('utf-8')
                            resp_json = json.loads(resp_data)
                            response_text = resp_json.get('response', '')
                            
                            # Parse model JSON response
                            parsed = json.loads(response_text)
                            
                            self.send_response(200)
                            self.send_header('Content-type', 'application/json')
                            self.end_headers()
                            self.wfile.write(json.dumps(parsed).encode('utf-8'))
                    except urllib.error.URLError as ue:
                        raise Exception(f"No se pudo conectar a Ollama en {ollama_url}. Verifica que este ejecutandose localmente. Error: {str(ue)}")
                    except json.JSONDecodeError:
                        raise Exception("Ollama no respondio con un JSON valido.")
                else:
                    raise Exception("Proveedor no soportado en backend.")
            except Exception as e:
                self.send_response(400)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode('utf-8'))
        elif self.path == '/api/ai/setup':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            try:
                data = json.loads(post_data.decode('utf-8'))
                model_name = data.get('model', 'llama3.2')
                
                if setup_status["step"] not in ["idle", "completed", "error"]:
                    self.send_response(400)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    self.wfile.write(b'{"error":"Instalacion en progreso."}')
                    return
                
                update_status("idle", 0.0)
                
                threading.Thread(target=run_ollama_setup_thread, args=(model_name,), daemon=True).start()
                
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"status":"started"}')
            except Exception as e:
                self.send_response(400)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

def start_server():
    socketserver.TCPServer.allow_reuse_address = True
    try:
        with socketserver.TCPServer(("", PORT), POSRequestHandler) as httpd:
            print(f"Server started on port {PORT}")
            httpd.serve_forever()
    except Exception as e:
        print(f"Error starting server on port {PORT}: {e}")

if __name__ == '__main__':
    os.chdir(BASE_DIR)
    init_sqlite_db()
    
    # Find a free port dynamically starting at 5000
    import socket
    test_port = 5000
    while test_port < 6000:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.bind(("", test_port))
                PORT = test_port
                break
        except OSError:
            test_port += 1
    
    # Start the HTTP server in a background thread
    server_thread = threading.Thread(target=start_server, daemon=True)
    server_thread.start()

    # Determine storage path for WebView cache/profile data (keeps Firebase config persistent)
    if getattr(sys, 'frozen', False):
        WEBVIEW_STORAGE = os.path.join(os.path.expanduser('~'), 'VariedadesLaLomita', 'webview_cache')
        os.makedirs(WEBVIEW_STORAGE, exist_ok=True)
    else:
        WEBVIEW_STORAGE = None

    # Open native desktop window pointing to localhost
    webview.create_window(
        'Variedades La Lomita',
        f'http://localhost:{PORT}',
        width=1600,
        height=960,
        resizable=True
    )
    webview.start(storage_path=WEBVIEW_STORAGE, private_mode=False)
