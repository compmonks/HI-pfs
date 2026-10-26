"""Exercise the lint refactor using temporary data and mocked external effects."""

import contextlib
import importlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
import zipfile

from scripts import generate_token, regenerate_token, utils


class TokenHelperTests(unittest.TestCase):
    """Keep token storage and both generation paths behaviorally covered."""

    def test_registry_round_trip(self):
        """All entry points use the same on-disk registry format."""
        with tempfile.TemporaryDirectory() as root:
            path = str(Path(root) / 'tokens' / 'tokens.json')
            with patch.object(generate_token, 'TOKENS_FILE', path):
                generate_token.save_tokens({'abc': 'café.zip'})
                self.assertEqual(generate_token.load_tokens(), {'abc': 'café.zip'})
            self.assertEqual(
                utils.load_token_registry(path, regenerate_token.logger), {'abc': 'café.zip'},
            )

    def test_token_creation_log_uses_non_secret_identifier(self):
        """The registry keeps the bearer token while the access log does not."""
        token = 'DummyBearerToken_123'
        with tempfile.TemporaryDirectory() as root, contextlib.ExitStack() as stack:
            base = Path(root)
            stack.enter_context(patch.object(
                generate_token, 'TOKENS_FILE', str(base / 'tokens' / 'tokens.json'),
            ))
            stack.enter_context(patch.object(
                generate_token, 'LOG_FILE', str(base / 'logs' / 'access.log'),
            ))
            stack.enter_context(patch.object(
                generate_token.secrets, 'token_urlsafe', return_value=token,
            ))

            self.assertEqual(
                generate_token.register_token('archive.zip', '2030-01-01', 'Generated'),
                token,
            )

            access_log = (base / 'logs' / 'access.log').read_text(encoding='utf-8')
            registry = json.loads(
                (base / 'tokens' / 'tokens.json').read_text(encoding='utf-8')
            )
            self.assertIn(token, registry)
            self.assertNotIn(token, access_log)
            self.assertIn(utils.token_fingerprint(token), access_log)

    def test_missing_and_corrupt_registry(self):
        """Missing files stay empty; malformed files retain logging and reporting."""
        logger = Mock()
        callback = Mock()
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'tokens.json'
            self.assertEqual(utils.load_token_registry(str(path), logger), {})
            path.write_text('{broken', encoding='utf-8')
            with patch.object(utils, 'report_exception') as report:
                self.assertEqual(utils.load_token_registry(str(path), logger, callback), {})
            callback.assert_called_once()
            report.assert_called_once()

    def test_registry_write_failure_is_reported_and_raised(self):
        """Callers must stop when the registry cannot be persisted."""
        with tempfile.TemporaryDirectory() as root:
            with patch.object(
                utils.tempfile, 'mkstemp', side_effect=PermissionError('read-only'),
            ):
                with patch.object(utils, 'report_exception') as report:
                    with self.assertRaises(PermissionError):
                        utils.save_token_registry(
                            str(Path(root) / 'tokens.json'), {}, Mock(),
                        )
            report.assert_called_once()

    def test_registry_replace_failure_preserves_previous_file(self):
        """A failed atomic replace must retain the last valid registry."""
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'tokens.json'
            path.write_text('{"old": "archive.zip"}', encoding='utf-8')
            with patch.object(utils.os, 'replace', side_effect=OSError('disk error')):
                with patch.object(utils, 'report_exception'):
                    with self.assertRaises(OSError):
                        utils.save_token_registry(
                            str(path), {'new': 'other.zip'}, Mock(),
                        )
            self.assertEqual(
                json.loads(path.read_text(encoding='utf-8')),
                {'old': 'archive.zip'},
            )
            self.assertEqual(list(Path(root).glob('.tokens-*.tmp')), [])

    def test_renewal_email_is_data_not_shell_code(self):
        """Filename and recipient punctuation cannot become shell commands."""
        email = 'recipient+test@example.invalid'
        filename = 'archive"$(touch unwanted).zip'
        with patch.object(utils.subprocess, 'run') as run:
            utils.send_renewal_email('abc', filename, email)
        run.assert_called_once()
        args, options = run.call_args
        self.assertEqual(args[0], ['mail', '-s', '🔁 HI-pfs Token Renewed', '--', email])
        self.assertIn(filename, options['input'])
        self.assertIn('/download?token=abc', options['input'])
        self.assertNotIn('shell', options)

    def test_folder_generation_preserves_archive_contents(self):
        """The original folder is removed only after creating its ZIP and token."""
        with tempfile.TemporaryDirectory() as root, contextlib.ExitStack() as stack:
            base = Path(root)
            folder = base / 'source'
            folder.mkdir()
            (folder / 'hello.txt').write_text('hello', encoding='utf-8')
            for name, value in (
                ('ZIPS_DIR', str(base / 'zips')),
                ('TOKENS_FILE', str(base / 'tokens' / 'tokens.json')),
                ('LOG_FILE', str(base / 'logs' / 'access.log')),
            ):
                stack.enter_context(patch.object(generate_token, name, value))
            stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
            stack.enter_context(patch.object(utils, 'report_exception'))
            generate_token.generate(str(folder))
            self.assertFalse(folder.exists())
            registry = generate_token.load_tokens()
            self.assertEqual(len(registry), 1)
            filename = next(iter(registry.values()))
            with zipfile.ZipFile(base / 'zips' / filename) as archive:
                self.assertEqual(archive.namelist(), ['hello.txt'])
                self.assertEqual(archive.read('hello.txt'), b'hello')

    def test_registry_failure_keeps_source(self):
        """An unpersisted token must never permit source-folder deletion."""
        with tempfile.TemporaryDirectory() as root, contextlib.ExitStack() as stack:
            folder = Path(root) / 'source'
            folder.mkdir()
            (folder / 'hello.txt').write_text('hello', encoding='utf-8')
            stack.enter_context(patch.object(generate_token, 'ZIPS_DIR', root))
            stack.enter_context(patch.object(
                generate_token, 'register_token', side_effect=OSError('read-only'),
            ))
            report = stack.enter_context(patch.object(utils, 'report_exception'))
            stack.enter_context(contextlib.redirect_stdout(io.StringIO()))

            generate_token.generate(str(folder))

            self.assertTrue(folder.exists())
            report.assert_called_once()

    def test_archive_failure_keeps_source(self):
        """A ZIP error must not delete the original folder or register a token."""
        with tempfile.TemporaryDirectory() as root, contextlib.ExitStack() as stack:
            folder = Path(root) / 'source'
            folder.mkdir()
            stack.enter_context(patch.object(generate_token, 'ZIPS_DIR', root))
            stack.enter_context(patch.object(
                generate_token, 'archive_folder', side_effect=OSError('disk full'),
            ))
            register = stack.enter_context(patch.object(generate_token, 'register_token'))
            report = stack.enter_context(patch.object(utils, 'report_exception'))
            stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
            generate_token.generate(str(folder))
            self.assertTrue(folder.exists())
            register.assert_not_called()
            report.assert_called_once()

    def test_regenerate_copies_external_zip_and_sends_link(self):
        """An external ZIP is retained and copied before its token is registered."""
        with tempfile.TemporaryDirectory() as root, contextlib.ExitStack() as stack:
            base = Path(root)
            source = base / 'archive.zip'
            source.write_bytes(b'archive-data')
            for name, value in (
                ('ZIPS_DIR', str(base / 'zips')),
                ('TOKENS_FILE', str(base / 'tokens' / 'tokens.json')),
                ('LOG_FILE', str(base / 'logs' / 'access.log')),
            ):
                stack.enter_context(patch.object(generate_token, name, value))
            send = stack.enter_context(patch.object(utils, 'send_renewal_email'))
            stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
            generate_token.regenerate(str(source), 'test@example.invalid')
            registry = generate_token.load_tokens()
            self.assertEqual(len(registry), 1)
            self.assertEqual((base / 'zips' / source.name).read_bytes(), source.read_bytes())
            send.assert_called_once_with(next(iter(registry)), source.name, 'test@example.invalid')

    def test_stage_zip_preserves_existing_archive(self):
        """A name collision copies to a timestamped filename, preserving both inputs."""
        with tempfile.TemporaryDirectory() as root:
            base = Path(root)
            zips = base / 'zips'
            zips.mkdir()
            (zips / 'archive.zip').write_bytes(b'old')
            source = base / 'archive.zip'
            source.write_bytes(b'new')
            with patch.object(generate_token, 'ZIPS_DIR', str(zips)):
                filename = generate_token.stage_zip(str(source))
                self.assertNotEqual(filename, source.name)
                self.assertEqual(generate_token.stage_zip(str(zips / filename)), filename)
            self.assertEqual((zips / filename).read_bytes(), b'new')
            self.assertEqual((zips / 'archive.zip').read_bytes(), b'old')

    def test_standalone_regeneration_cli(self):
        """The alternate renewal command still updates the registry and sends once."""
        with tempfile.TemporaryDirectory() as root, contextlib.ExitStack() as stack:
            base = Path(root)
            (base / 'archive.zip').write_bytes(b'zip')
            stack.enter_context(patch.object(regenerate_token, 'ZIPS_DIR', root))
            stack.enter_context(patch.object(
                regenerate_token, 'TOKENS_FILE', str(base / 'tokens.json'),
            ))
            stack.enter_context(patch.object(
                sys, 'argv', ['regenerate_token.py', 'archive.zip', 'test@example.invalid'],
            ))
            send = stack.enter_context(patch.object(utils, 'send_renewal_email'))
            stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
            regenerate_token.main()
            registry = json.loads((base / 'tokens.json').read_text(encoding='utf-8'))
            self.assertEqual(list(registry.values()), ['archive.zip'])
            send.assert_called_once_with(
                next(iter(registry)), 'archive.zip', 'test@example.invalid',
            )

    def test_direct_script_imports(self):
        """Installed scripts import beside utils.py without a package or repository path."""
        scripts = Path(__file__).resolve().parents[1] / 'scripts'
        environment = {key: value for key, value in os.environ.items() if key != 'PYTHONPATH'}
        with tempfile.TemporaryDirectory() as root:
            for name in ('generate_token.py', 'regenerate_token.py', 'utils.py'):
                (Path(root) / name).write_bytes((scripts / name).read_bytes())
            result = subprocess.run(
                [sys.executable, '-c', 'import generate_token; import regenerate_token'],
                cwd=root, env=environment, capture_output=True, text=True,
                check=False, timeout=10,
            )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_package_imports(self):
        """Both token commands are importable under their repository package name."""
        for name in ('scripts.generate_token', 'scripts.regenerate_token'):
            self.assertIsNotNone(importlib.import_module(name))


if __name__ == '__main__':
    unittest.main()
