import json
import time
import random
import urllib.request
import urllib.error
import urllib.parse
from datetime import datetime, timezone

API_KEY = "AIzaSyCdIejGnwlpWbT_dsrr9zgE4iy6CfAUak4"
PROJECT_ID = "variedades-la-lomita"
FIRESTORE_BASE = f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents"

def genId():
    chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
    val = int(time.time() * 1000)
    base36 = ""
    while val > 0:
        base36 = chars[val % 36] + base36
        val //= 36
    r = "".join(random.choice(chars) for _ in range(6))
    return base36 + r

def to_firestore_val(val):
    if isinstance(val, bool):
        return {"booleanValue": val}
    elif isinstance(val, int):
        return {"integerValue": str(val)}
    elif isinstance(val, float):
        return {"doubleValue": val}
    elif isinstance(val, str):
        return {"stringValue": val}
    elif isinstance(val, list):
        return {"arrayValue": {"values": [to_firestore_val(v) for v in val]}}
    elif isinstance(val, dict):
        fields = {k: to_firestore_val(v) for k, v in val.items()}
        return {"mapValue": {"fields": fields}}
    elif val is None:
        return {"nullValue": None}
    else:
        return {"stringValue": str(val)}

def to_firestore_doc(data):
    return {"fields": {k: to_firestore_val(v) for k, v in data.items()}}

def firestore_patch(collection, doc_id, data):
    safe_id = urllib.parse.quote(doc_id, safe="")
    url = f"{FIRESTORE_BASE}/{collection}/{safe_id}?key={API_KEY}"
    body = json.dumps(to_firestore_doc(data)).encode("utf-8")
    req = urllib.request.Request(url, data=body, method="PATCH")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8") if e.fp else str(e)
        raise Exception(f"HTTP {e.code}: {err}")

def main():
    print("Conectando a Firestore via REST API...")
    print(f"Proyecto: {PROJECT_ID}\n")

    now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    # ---- PROVEEDORES ----
    print("=== PROVEEDORES ===")
    suppliers = [
        {"name": "Coca-Cola Co", "contact": "3001234567", "address": "Calle 123"},
        {"name": "Distribuidora de Dulces y Snacks La Dulce", "contact": "3123456789", "address": "Av. Principal 45-12"},
        {"name": "Papeleria y Utiles El Estudioso", "contact": "3109876543", "address": "Calle 10 # 5-20"},
        {"name": "TecnoAccesorios del Centro", "contact": "3201112222", "address": "Cra 15 # 12-34"},
        {"name": "Distribuidora Alpina Local", "contact": "3154445555", "address": "Zona Industrial Bodega 5"},
    ]

    supp_ids = {}
    for s in suppliers:
        sid = genId()
        firestore_patch("suppliers", sid, {
            "id": sid, "name": s["name"], "contact": s["contact"],
            "address": s["address"], "createdAt": now, "updatedAt": now,
        })
        supp_ids[s["name"]] = sid
        print(f"  Proveedor: {s['name']}")
    print("  -> OK\n")

    # ---- PRODUCTOS ----
    print("=== PRODUCTOS Y PRECIOS ===")
    prods = {
        "Coca-Cola Co": [
            ("Coca-Cola 350ml", 1500, 2200, 24, "7702004001234", "Bebidas"),
            ("Sprite 1.5L", 3200, 4500, 2, "7702004001235", "Bebidas"),
            ("Fanta Naranja 1.5L", 3200, 4500, 1, "7702004001236", "Bebidas"),
            ("Agua Cristal 600ml", 1000, 1800, 15, "7702004001237", "Bebidas"),
        ],
        "Distribuidora de Dulces y Snacks La Dulce": [
            ("Papas Margarita Limon", 1800, 2500, 20, "7702007004321", "Comida"),
            ("Papas Margarita Pollo", 1800, 2500, 0, "7702007004322", "Comida"),
            ("Chocolatina Jet 12g", 500, 800, 50, "7702007004323", "Comida"),
            ("Galletas Oreo", 1000, 1500, 30, "7702007004324", "Comida"),
            ("Gomas Trululu", 1200, 1800, 3, "7702007004325", "Comida"),
        ],
        "Papeleria y Utiles El Estudioso": [
            ("Cuaderno Cuadriculado 100hj", 2500, 4000, 40, "7703004005678", "Papeleria"),
            ("Cuaderno Rayado 100hj", 2500, 4000, 0, "7703004005679", "Papeleria"),
            ("Lapicero Negro Bic", 600, 1000, 100, "7703004005680", "Papeleria"),
            ("Lapicero Rojo Bic", 600, 1000, 5, "7703004005681", "Papeleria"),
            ("Borrador de Nata", 400, 800, 45, "7703004005682", "Papeleria"),
            ("Sacapuntas con Deposito", 800, 1500, 30, "7703004005683", "Papeleria"),
        ],
        "TecnoAccesorios del Centro": [
            ("Cargador Carga Rapida USB-C", 8000, 15000, 1, "7704005001111", "Tecnologia"),
            ("Cable USB-C a USB-C 1m", 3000, 7000, 15, "7704005001112", "Tecnologia"),
            ("Audifonos In-Ear Basicos", 5000, 12000, 0, "7704005001113", "Tecnologia"),
            ("Vidrio Templado Universal", 2000, 6000, 25, "7704005001114", "Tecnologia"),
        ],
        "Distribuidora Alpina Local": [
            ("Yogurt Alpina Fresa 150g", 1500, 2200, 15, "7705006002222", "Lacteos"),
            ("Yogurt Alpina Melocoton 150g", 1500, 2200, 1, "7705006002223", "Lacteos"),
            ("Arequipe Alpina 220g", 3500, 5000, 8, "7705006002224", "Lacteos"),
            ("Quesito Alpina 100g", 2800, 4000, 10, "7705006002225", "Lacteos"),
        ],
    }

    prod_ids = {}
    prod_links = []
    for sname, items in prods.items():
        sid = supp_ids[sname]
        for name, cost, sale, stock, barcode, cat in items:
            pid = genId()
            prod_ids[name] = pid

            firestore_patch("products", pid, {
                "id": pid, "name": name, "category": cat,
                "initialStock": stock, "unlimited": False,
                "barcode": barcode, "active": True,
                "createdAt": now, "updatedAt": now,
            })

            lid = genId()
            firestore_patch("prodSuppliers", lid, {
                "id": lid, "productId": pid, "supplierId": sid,
                "purchasePrice": cost, "salePrice": sale,
                "isDefault": True, "createdAt": now, "updatedAt": now,
            })

            firestore_patch("historico_precios", genId(), {
                "id": genId(), "productId": pid, "supplierId": sid,
                "purchasePrice": cost, "salePrice": sale,
                "reason": "Registro inicial", "createdAt": now,
            })

            if stock > 0:
                firestore_patch("inventario_movimientos", genId(), {
                    "id": genId(), "productId": pid, "productName": name,
                    "type": "Ajuste", "prevQty": 0, "newQty": stock,
                    "reason": "Stock inicial", "user": "administrador",
                    "createdAt": now, "date": datetime.now().strftime("%Y-%m-%d"),
                })

            print(f"  {name} ({cat}) - ${sale}")
            prod_links.append((pid, sid, cost, sale))
    print("  -> OK\n")

    # ---- CLIENTES ----
    print("=== CLIENTES ===")
    clients = {
        "Carlos Mendoza": ("3119876543", 50000),
        "Maria Camila Delgado": ("3151234567", 80000),
        "Juan Fernando Restrepo": ("3004567890", 30000),
        "Diana Marcela Ortiz": ("3187654321", 60000),
    }
    for name, (phone, limit) in clients.items():
        firestore_patch("clientDetails", name, {"phone": phone, "limit": limit})
        print(f"  Cliente: {name}")
    print("  -> OK\n")

    # ---- CATEGORIAS DE DISTRIBUCION ----
    print("=== CATEGORIAS DE DISTRIBUCION ===")
    cats = [
        ("cat_0", "Caja Principal", "daily", 0),
        ("cat_1", "Sueldo Mama (Semanal)", "weekly", 1),
        ("cat_2", "Sueldo Papa (Semanal)", "weekly", 2),
        ("cat_3", "Arriendo", "monthly", 3),
        ("cat_4", "Facturas Casa y Comida", "weekly", 4),
        ("cat_5", "Deudas del Negocio", "weekly", 5),
        ("cat_6", "Deudas Personales", "weekly", 6),
        ("cat_7", "Caja Chica", "daily", 7),
        ("cat_8", "Facturas (Proveedores)", "weekly", 8),
        ("cat_9", "Reposicion de Mercancia", "weekly", 9),
    ]
    for cid, cname, ctype, corder in cats:
        firestore_patch("distributionCategories", cid, {
            "id": cid, "name": cname, "type": ctype,
            "order": corder, "active": True,
            "createdAt": now, "updatedAt": now,
        })
        print(f"  {cname} ({ctype})")
    print("  -> OK\n")

    # ---- SETTINGS ----
    print("=== SETTINGS ===")
    firestore_patch("settings", "general", {
        "businessName": "Variedades La Lomita", "currency": "$",
        "aiProvider": "local", "ollamaUrl": "http://localhost:11434",
        "ollamaModel": "llama3.2", "createdAt": now, "updatedAt": now,
    })
    print("  -> OK\n")

    print("=" * 50)
    print("  DATOS SUBIDOS A FIRESTORE!")
    print(f"  Proyecto: {PROJECT_ID}")
    print(f"  5 proveedores, {len(prod_ids)} productos,")
    print(f"  4 clientes, 10 categorias, settings")
    print("=" * 50)

if __name__ == "__main__":
    main()
