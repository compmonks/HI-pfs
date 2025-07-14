#!/usr/bin/env python3
import os
import json
import secrets
import sys
from datetime import datetime

BASE_DIR = os.path.abspath(os.path.dirname(__file__))
TOKENS_FILE = os.path.join(BASE_DIR, 'tokens', 'tokens.json')
ZIPS_DIR = os.path.join(BASE_DIR, 'zips')

def load_tokens():
    if not os.path.exists(TOKENS_FILE):
        return {}
    try:
        with open(TOKENS_FILE, 'r') as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return {}

def save_tokens(tokens):
    os.makedirs(os.path.dirname(TOKENS_FILE), exist_ok=True)
    with open(TOKENS_FILE, 'w') as f:
        json.dump(tokens, f, indent=2)

# Expect two arguments: the ZIP filename and the destination email address
if len(sys.argv) < 3:
    print("Usage: regenerate_token.py <zip_filename> <email>")
    sys.exit(1)

zip_filename = sys.argv[1]
email = sys.argv[2]
zip_path = os.path.join(ZIPS_DIR, zip_filename)

if not os.path.isfile(zip_path):
    print(f" ZIP not found: {zip_path}")
    sys.exit(1)

# Generate new token
token = secrets.token_urlsafe(16)

# Load or create token registry
os.makedirs(os.path.dirname(TOKENS_FILE), exist_ok=True)
tokens = load_tokens()

tokens[token] = zip_filename
save_tokens(tokens)

# Send email notification
url = f"http://<your-node>:8082/download?token={token}"
subject = "🔁 HI-pfs Token Renewed"
message = f"""Your download token has expired and was renewed.

File: {zip_filename}
Link: {url}"""

os.system(f'echo "{message}" | mail -s "{subject}" "{email}"')

print(f" New token generated: {token}")
