import logging
import os
import json
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
    except Exception:
        return False


def report_exception(logger: logging.Logger, context: str, exc: Exception) -> None:
    """Log an exception and attempt to create a GitHub issue."""
    logger.error("%s: %s", context, exc)
    tb = traceback.format_exc()
    logger.debug(tb)
    title = f"HI-pfs error: {context}"
    body = f"```\n{tb}\n```"
    create_github_issue(title, body)
