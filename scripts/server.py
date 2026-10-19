"""Serve token-protected downloads and node health endpoints."""

import os
from datetime import datetime
import re
import subprocess

from flask import Flask, request, send_file, abort

try:
    from . import utils
except ImportError:  # Standalone scripts installed beside utils.py.
    import utils

logger = utils.setup_logger(__name__)

app = Flask(__name__)

if hasattr(app, 'errorhandler'):
    @app.errorhandler(Exception)
    def handle_exception(e):
        """Report unexpected request errors through the existing error hook."""
        utils.report_exception(logger, 'server_exception', e)
        return 'Internal Server Error', 500

BASE_DIR = os.path.abspath(os.path.dirname(__file__))
TOKENS_FILE = os.path.join(BASE_DIR, 'tokens', 'tokens.json')
ZIPS_DIR = os.path.join(BASE_DIR, 'zips')
LOG_FILE = os.path.join(BASE_DIR, 'logs', 'access.log')
CID_FILE = os.path.expanduser('~/ipfs-admin/shared-cids.txt')
ENV_FILE = '/etc/hi-pfs.env'

# Load EMAIL from environment config
def get_email():
    """Read the notification address from the node configuration."""
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE, 'r', encoding='utf-8') as f:
            for line in f:
                if line.startswith("EMAIL="):
                    return line.strip().split("=", 1)[1]
    return "admin@example.com"

def log_event(message):
    """Append the request event to the access log and console logger."""
    timestamp = datetime.utcnow().isoformat()
    log_line = f"[{timestamp}] {request.remote_addr} {message}\n"
    with open(LOG_FILE, 'a', encoding='utf-8') as f:
        f.write(log_line)
    logger.info(message)

def sanitize_token(token):
    """Accept only URL-safe token characters."""
    return re.fullmatch(r"[A-Za-z0-9_\-]+", token)

def is_safe_path(directory, path):
    """Ensure the requested path is contained within the directory."""
    abs_directory = os.path.realpath(directory)
    abs_path = os.path.realpath(path)
    return os.path.commonpath([abs_path, abs_directory]) == abs_directory

def load_tokens():
    """Read the token registry and log malformed or unreadable files."""
    return utils.load_token_registry(TOKENS_FILE, logger, on_error=log_event)


def save_tokens(tokens):
    """Persist token updates with the shared error reporting."""
    utils.save_token_registry(TOKENS_FILE, tokens, logger)

@app.route('/download', methods=['GET'])
def download():
    """Validate and consume a token before returning its ZIP file."""
    token = request.args.get('token')
    if not token or not sanitize_token(token):
        abort(400, description="Invalid or missing token.")

    tokens = load_tokens()

    if token not in tokens:
        log_event(f"REJECTED invalid token: {token}")
        abort(403, description="Invalid token.")

    filename = tokens[token]
    zip_path = os.path.join(ZIPS_DIR, filename)

    if not is_safe_path(ZIPS_DIR, zip_path):
        log_event(f"REJECTED unsafe path: {zip_path}")
        abort(400, description="Invalid file path.")

    if not os.path.isfile(zip_path):
        log_event(f"ERROR missing ZIP: {filename}")
        abort(404, description="File not found.")

    log_event(f"DOWNLOAD token={token} file={filename}")

    # Invalidate token
    del tokens[token]
    save_tokens(tokens)

    # Regenerate token and send email
    email = get_email()
    # Renewal runs independently; waiting here would delay the download response.
    # pylint: disable-next=consider-using-with
    subprocess.Popen([
        "python3", os.path.join(BASE_DIR, "generate_token.py"),
        "--regenerate", filename, email,
    ])

    return send_file(zip_path, as_attachment=True)

@app.route('/shared-cids.txt', methods=['GET'])
def serve_cid_file():
    """Return the shared CID list when available."""
    if os.path.exists(CID_FILE):
        return send_file(CID_FILE, mimetype='text/plain')
    return "CID file not found", 404

@app.route('/health', methods=['GET'])
def health():
    """Provide the node's lightweight health response."""
    return "OK", 200

if __name__ == '__main__':
    try:
        app.run(host='0.0.0.0', port=8082)
    except OSError as e:
        utils.report_exception(logger, 'flask_run', e)
