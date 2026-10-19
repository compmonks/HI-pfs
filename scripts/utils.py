"""Shared logging, token storage and notification helpers."""

from http.client import HTTPException
import logging
import os
import json
import subprocess
import traceback
from urllib import request


def setup_logger(name: str) -> logging.Logger:
    """Configure and return a simple console logger."""
    logger = logging.getLogger(name)
    if not logger.handlers:
        logger.setLevel(logging.INFO)
        handler = logging.StreamHandler()
        fmt = logging.Formatter('%(asctime)s [%(levelname)s] %(message)s')
        handler.setFormatter(fmt)
        logger.addHandler(handler)
    return logger


def create_github_issue(title: str, body: str) -> bool:
    """Create a GitHub issue using environment credentials.

    Requires GITHUB_TOKEN and GITHUB_REPOSITORY environment variables.
    """
    token = os.getenv('GITHUB_TOKEN')
    repo = os.getenv('GITHUB_REPOSITORY')
    if not token or not repo:
        return False

    api_url = f'https://api.github.com/repos/{repo}/issues'
    data = json.dumps({'title': title, 'body': body}).encode()
    req = request.Request(api_url, data=data, method='POST')
    req.add_header('Authorization', f'token {token}')
    req.add_header('Accept', 'application/vnd.github+json')

    try:
        with request.urlopen(req) as resp:
            return 200 <= resp.status < 300
    except (OSError, HTTPException, ValueError):
        return False


def report_exception(logger: logging.Logger, context: str, exc: Exception) -> None:
    """Log an exception and attempt to create a GitHub issue."""
    logger.error("%s: %s", context, exc)
    tb = traceback.format_exc()
    logger.debug(tb)
    title = f"HI-pfs error: {context}"
    body = f"```\n{tb}\n```"
    create_github_issue(title, body)


def load_token_registry(path, logger, on_error=None):
    """Read tokens, preserving the callers' missing/corrupt-file fallback."""
    if not os.path.exists(path):
        return {}
    try:
        with open(path, 'r', encoding='utf-8') as token_file:
            return json.load(token_file)
    except (ValueError, OSError) as exc:
        if on_error is not None:
            on_error(f"ERROR reading tokens file: {exc}")
        report_exception(logger, 'load_tokens', exc)
        return {}


def save_token_registry(path, tokens, logger):
    """Write the registry using the existing error-reporting policy."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        with open(path, 'w', encoding='utf-8') as token_file:
            json.dump(tokens, token_file, indent=2)
    except OSError as exc:
        report_exception(logger, 'save_tokens', exc)


def send_renewal_email(token, zip_filename, email):
    """Send renewal text as data, without interpolating it into a shell."""
    url = f"http://<your-node>:8082/download?token={token}"
    message = (
        "Your download token has expired and was renewed.\n\n"
        f"File: {zip_filename}\nLink: {url}\n"
    )
    subprocess.run(
        ['mail', '-s', '🔁 HI-pfs Token Renewed', '--', email],
        input=message, text=True, encoding='utf-8', check=False,
    )
