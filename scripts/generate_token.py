"""Create token-protected ZIP downloads or renew a token for an existing ZIP."""

from datetime import datetime
import os
import secrets
import shutil
import sys
import zipfile

try:
    from . import utils
except ImportError:  # Standalone scripts installed beside utils.py.
    import utils

logger = utils.setup_logger('generate_token')

BASE_DIR = os.path.abspath(os.path.dirname(__file__))
TOKENS_FILE = os.path.join(BASE_DIR, 'tokens', 'tokens.json')
ZIPS_DIR = os.path.join(BASE_DIR, 'zips')
LOG_FILE = os.path.join(BASE_DIR, 'logs', 'access.log')


def load_tokens():
    """Load the current token registry."""
    return utils.load_token_registry(TOKENS_FILE, logger)


def save_tokens(tokens):
    """Persist the updated token registry."""
    utils.save_token_registry(TOKENS_FILE, tokens, logger)


def register_token(zip_filename, timestamp, action):
    """Save a fresh token and append its creation event to the access log."""
    token = secrets.token_urlsafe(16)
    tokens = load_tokens()
    tokens[token] = zip_filename
    save_tokens(tokens)
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    with open(LOG_FILE, 'a', encoding='utf-8') as log_file:
        token_id = utils.token_fingerprint(token)
        log_file.write(
            f"[{timestamp}] {action} token_id={token_id} for file={zip_filename}\n"
        )
    return token


def print_token(token, zip_filename):
    """Display the created token, filename and download URL."""
    print("✅ Token generated!")
    print(f"🔐 Token: {token}")
    print(f"📦 File:  {zip_filename}")
    print(f"🌐 Link:  http://<your-node>:8082/download?token={token}")


def stage_zip(zip_arg):
    """Copy an external ZIP into the serving directory without overwriting it."""
    os.makedirs(ZIPS_DIR, exist_ok=True)
    zip_basename = os.path.basename(zip_arg)
    if os.path.abspath(os.path.dirname(zip_arg)) == os.path.abspath(ZIPS_DIR):
        return zip_basename
    dest_path = os.path.join(ZIPS_DIR, zip_basename)
    if os.path.exists(dest_path):
        timestamp = datetime.utcnow().strftime("%Y%m%d-%H%M%S")
        base_name, ext = os.path.splitext(zip_basename)
        dest_path = os.path.join(ZIPS_DIR, f"{base_name}_{timestamp}{ext}")
    shutil.copy(zip_arg, dest_path)
    return os.path.basename(dest_path)


def regenerate(zip_arg, email=None):
    """Renew an existing ZIP's token, optionally notifying the recipient."""
    try:
        zip_filename = stage_zip(zip_arg)
        timestamp = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
        token = register_token(zip_filename, timestamp, "Regenerated")
        if email:
            utils.send_renewal_email(token, zip_filename, email)
        print_token(token, zip_filename)
    except (OSError, ValueError) as exc:
        utils.report_exception(logger, 'generate_token_regenerate', exc)


def archive_folder(folder, zip_path):
    """Write the folder contents into a ZIP using relative archive paths."""
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zip_file:
        for root, _, files in os.walk(folder):
            for filename in files:
                abs_file = os.path.join(root, filename)
                zip_file.write(abs_file, os.path.relpath(abs_file, start=folder))


def generate(folder):
    """Archive a folder, register its token and remove the original folder."""
    try:
        timestamp = datetime.utcnow().strftime("%Y%m%d-%H%M%S")
        folder_name = os.path.basename(folder.rstrip("/"))
        zip_filename = f"{folder_name}_{timestamp}.zip"
        print(f"🗜️ Zipping folder: {folder}")
        os.makedirs(ZIPS_DIR, exist_ok=True)
        archive_folder(folder, os.path.join(ZIPS_DIR, zip_filename))
        token = register_token(zip_filename, timestamp, "Generated")
        try:
            shutil.rmtree(folder)
            print(f"🧹 Original folder '{folder}' deleted.")
        except OSError as exc:
            logger.warning("Could not delete folder %s: %s", folder, exc)
        print_token(token, zip_filename)
    except (OSError, ValueError, RuntimeError, zipfile.BadZipFile) as exc:
        utils.report_exception(logger, 'generate_token', exc)


def main():
    """Dispatch the folder and existing-ZIP command-line forms."""
    if len(sys.argv) < 2:
        print("Usage: python3 generate_token.py <folder> or "
              "python3 generate_token.py --regenerate <zip_file> [email]")
        sys.exit(1)
    if sys.argv[1] == "--regenerate":
        if len(sys.argv) < 3:
            print("Usage: python3 generate_token.py --regenerate <zip_file> [email]")
            sys.exit(1)
        zip_arg = sys.argv[2]
        if not os.path.isfile(zip_arg):
            print(f"❌ Error: ZIP file not found: {zip_arg}")
            sys.exit(1)
        regenerate(zip_arg, sys.argv[3] if len(sys.argv) > 3 else None)
        return
    folder = sys.argv[1]
    if not os.path.isdir(folder):
        print(f"❌ Error: Folder not found: {folder}")
        sys.exit(1)
    generate(folder)


if __name__ == '__main__':
    main()
