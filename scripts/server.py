from flask import Flask, request, send_file, abort
import json
import os
from datetime import datetime

app = Flask(__name__)

TOKENS_FILE = 'tokens/tokens.json'
ZIPS_DIR = 'zips'
LOG_FILE = 'logs/access.log'

def log_event(message):
    with open(LOG_FILE, 'a') as f:
        timestamp = datetime.utcnow().isoformat()
        f.write(f"[{timestamp}] {message}\n")

@app.route('/download', methods=['GET'])
def download():
    token = request.args.get('token')
    if not token:
        abort(400, description="Token required.")

    if not os.path.exists(TOKENS_FILE):
        abort(500, description="Token registry missing.")

    with open(TOKENS_FILE, 'r') as f:
        tokens = json.load(f)

    if token not in tokens:
        log_event(f"REJECTED unknown token: {token}")
        abort(403, description="Invalid token.")

    filename = tokens[token]
    zip_path = os.path.join(ZIPS_DIR, filename)

    if not os.path.exists(zip_path):
        log_event(f"ERROR file not found: {filename}")
        abort(404, description="File not found.")

    log_event(f"ACCEPTED {request.remote_addr} downloaded {filename}")
    return send_file(zip_path, as_attachment=True)

@app.route('/shared-cids.txt', methods=['GET'])
def serve_cid_file():
    cid_path = os.path.expanduser('~/ipfs-admin/shared-cids.txt')
    if os.path.exists(cid_path):
        return send_file(cid_path, mimetype='text/plain')
    else:
        return "CID file not found", 404

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8082)
