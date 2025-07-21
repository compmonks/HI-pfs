import os
import json
import secrets
import sys
from datetime import datetime
import zipfile
import shutil

try:
    from utils import setup_logger, report_exception
except ImportError:
    from .utils import setup_logger, report_exception

logger = setup_logger('generate_token')

BASE_DIR = os.path.abspath(os.path.dirname(__file__))
TOKENS_FILE = os.path.join(BASE_DIR, 'tokens', 'tokens.json')
ZIPS_DIR = os.path.join(BASE_DIR, 'zips')
LOG_FILE = os.path.join(BASE_DIR, 'logs', 'access.log')

def load_tokens():
    if not os.path.exists(TOKENS_FILE):
        return {}
    try:
        with open(TOKENS_FILE, 'r') as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        report_exception(logger, 'load_tokens', e)
        return {}

def save_tokens(tokens):
    os.makedirs(os.path.dirname(TOKENS_FILE), exist_ok=True)
    try:
        with open(TOKENS_FILE, 'w') as f:
            json.dump(tokens, f, indent=2)
    except OSError as e:
        report_exception(logger, 'save_tokens', e)

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 generate_token.py <folder>")
        sys.exit(1)

    folder = sys.argv[1]
    if not os.path.isdir(folder):
        print(f"❌ Error: Folder not found: {folder}")
        sys.exit(1)

    try:
        # Generate token and timestamped ZIP filename
        token = secrets.token_urlsafe(16)
        timestamp = datetime.utcnow().strftime("%Y%m%d-%H%M%S")
        folder_name = os.path.basename(folder.rstrip("/"))
        zip_filename = f"{folder_name}_{timestamp}.zip"
        zip_path = os.path.join(ZIPS_DIR, zip_filename)

        print(f"🗜️ Zipping folder: {folder}")
        os.makedirs(ZIPS_DIR, exist_ok=True)
        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
            for root, _, files in os.walk(folder):
                for file in files:
                    abs_file = os.path.join(root, file)
                    arcname = os.path.relpath(abs_file, start=folder)
                    zipf.write(abs_file, arcname)

        os.makedirs(os.path.dirname(TOKENS_FILE), exist_ok=True)
        tokens = load_tokens()
        tokens[token] = zip_filename
        save_tokens(tokens)

        token_log_line = (
            f"[{timestamp}] Generated token={token} for file={zip_filename}\n"
        )
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        with open(LOG_FILE, 'a') as logf:
            logf.write(token_log_line)

        try:
            shutil.rmtree(folder)
            print(f"🧹 Original folder '{folder}' deleted.")
        except Exception as e:
            logger.warning("Could not delete folder %s: %s", folder, e)

        print("✅ Token generated!")
        print(f"🔐 Token: {token}")
        print(f"📦 File:  {zip_filename}")
        print(f"🌐 Link:  http://<your-node>:8082/download?token={token}")
    except Exception as e:
        report_exception(logger, 'generate_token', e)


if __name__ == '__main__':
    main()
