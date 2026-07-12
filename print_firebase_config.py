import sqlite3
import json

conn = sqlite3.connect('lalomita.db')
c = conn.cursor()
c.execute("SELECT val FROM app_state WHERE key='pos_data'")
row = c.fetchone()
if row:
    data = json.loads(row[0])
    print("Settings keys:", data.get('settings', {}).keys())
    print("firebaseConfig:", data.get('settings', {}).get('firebaseConfig'))
    # Also let's print all of settings to see what is there
    print("Full settings:", data.get('settings', {}))
conn.close()
