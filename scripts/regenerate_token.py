#!/usr/bin/env python3
"""Renew a download token for an existing ZIP and notify its recipient."""

import os
import secrets
import sys

try:
    from . import utils
except ImportError:  # Standalone scripts installed beside utils.py.
    import utils

logger = utils.setup_logger('regenerate_token')

BASE_DIR = os.path.abspath(os.path.dirname(__file__))
TOKENS_FILE = os.path.join(BASE_DIR, 'tokens', 'tokens.json')
ZIPS_DIR = os.path.join(BASE_DIR, 'zips')

def main():
    """Validate CLI arguments, renew a token and send its download link."""
    if len(sys.argv) < 3:
        print("Usage: regenerate_token.py <zip_filename> <email>")
        sys.exit(1)

    zip_filename = sys.argv[1]
    email = sys.argv[2]
    zip_path = os.path.join(ZIPS_DIR, zip_filename)

    if not os.path.isfile(zip_path):
        print(f"❌ ZIP not found: {zip_path}")
        sys.exit(1)

    try:
        token = secrets.token_urlsafe(16)
        os.makedirs(os.path.dirname(TOKENS_FILE), exist_ok=True)
        tokens = utils.load_token_registry(TOKENS_FILE, logger)
        tokens[token] = zip_filename
        utils.save_token_registry(TOKENS_FILE, tokens, logger)

        utils.send_renewal_email(token, zip_filename, email)
        print(f" New token generated: {token}")
    except (OSError, ValueError) as e:
        utils.report_exception(logger, 'regenerate_token', e)

if __name__ == '__main__':
    main()
