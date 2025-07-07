import os
import json
import secrets
import sys
from datetime import datetime

TOKENS_FILE = 'tokens/tokens.json'
ZIPS_DIR = 'zips'

if len(sys.argv) < 2:
    print("Usage: python3 generate_token.py <folder>")
    sys.exit(1)

folder = sys.argv[1]
if not os.path.isdir(folder):
    print(f"Error: Folder not found: {folder}")
    sys.exit(1)

# Generate token and filename
token = secrets.token_urlsafe(16)
timestamp = datetime.utcnow().strftime("%Y%m%d-%H%M%S")
folder_name = os.path.basename(folder.rstrip("/"))
zip_filename = f"{folder_name}_{timestamp}.zip"
zip_path = os.path.join(ZIPS_DIR, zip_filename)

# Create zip archive
os.system(f"zip -r '{zip_path}' '{folder}' > /dev/null")

# Load or create token registry
if os.path.exists(TOKENS_FILE):
    with open(TOKENS_FILE, 'r') as f:
        tokens = json.load(f)
else:
    tokens = {}

# Register token
tokens[token] = zip_filename
with open(TOKENS_FILE, 'w') as f:
    json.dump(tokens, f, indent=2)

print(f"✅ Token generated: {token}")
print(f"   Download link: http://<your-node>:8082/download?token={token}")