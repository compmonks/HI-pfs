import os
import json
import secrets
import sys
from datetime import datetime
import zipfile
import shutil

BASE_DIR = os.path.abspath(os.path.dirname(__file__))
TOKENS_FILE = os.path.join(BASE_DIR, 'tokens', 'tokens.json')
ZIPS_DIR = os.path.join(BASE_DIR, 'zips')
LOG_FILE = os.path.join(BASE_DIR, 'logs', 'access.log')

if len(sys.argv) < 2:
    print("Usage: python3 generate_token.py <folder>")
    sys.exit(1)

folder = sys.argv[1]
if not os.path.isdir(folder):
    print(f"❌ Error: Folder not found: {folder}")
    sys.exit(1)

# Generate token and timestamped ZIP filename
token = secrets.token_urlsafe(16)
timestamp = datetime.utcnow().strftime("%Y%m%d-%H%M%S")
folder_name = os.path.basename(folder.rstrip("/"))
zip_filename = f"{folder_name}_{timestamp}.zip"
zip_path = os.path.join(ZIPS_DIR, zip_filename)

# Create zip file
print(f"🗜️ Zipping folder: {folder}")
os.makedirs(ZIPS_DIR, exist_ok=True)
with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
    for root, dirs, files in os.walk(folder):
        for file in files:
            abs_file = os.path.join(root, file)
            arcname = os.path.relpath(abs_file, start=folder)
            zipf.write(abs_file, arcname)

# Load or create token registry
os.makedirs(os.path.dirname(TOKENS_FILE), exist_ok=True)
tokens = {}
if os.path.exists(TOKENS_FILE):
    with open(TOKENS_FILE, 'r') as f:
        tokens = json.load(f)

tokens[token] = zip_filename
with open(TOKENS_FILE, 'w') as f:
    json.dump(tokens, f, indent=2)

# Log generation
token_log_line = f"[{timestamp}] Generated token={token} for file={zip_filename}\n"
os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
with open(LOG_FILE, 'a') as logf:
    logf.write(token_log_line)

# Cleanup original folder after success
try:
    shutil.rmtree(folder)
    print(f"🧹 Original folder '{folder}' deleted.")
except Exception as e:
    print(f"⚠️ Warning: Could not delete folder '{folder}': {e}")

# Output
print("✅ Token generated!")
print(f"🔐 Token: {token}")
print(f"📦 File:  {zip_filename}")
print(f"🌐 Link:  http://<your-node>:8082/download?token={token}")