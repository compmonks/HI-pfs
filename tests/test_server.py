"""Regression checks for server token validation and path containment."""

from scripts import server


def test_valid_token_returns_match():
    """URL-safe tokens remain valid."""
    token = 'ValidToken_123-abc'
    assert server.sanitize_token(token) is not None


def test_invalid_token_space_returns_none():
    """Whitespace is not accepted in tokens."""
    assert server.sanitize_token('invalid token') is None


def test_invalid_token_special_char_returns_none():
    """Shell punctuation is not accepted in tokens."""
    assert server.sanitize_token('invalid$token') is None


def test_is_safe_path_accepts_inside(tmp_path):
    """Files inside the download directory are permitted."""
    base = tmp_path
    file_path = base / 'file.txt'
    file_path.write_text('data')
    assert server.is_safe_path(str(base), str(file_path))


def test_is_safe_path_rejects_outside(tmp_path):
    """Paths outside the download directory are rejected."""
    base = tmp_path
    outside = tmp_path / '..' / 'evil.txt'
    assert not server.is_safe_path(str(base), str(outside.resolve()))


def test_load_tokens_missing_returns_empty_dict(tmp_path, monkeypatch):
    """A missing registry retains the empty-registry fallback."""
    monkeypatch.setattr(server, 'TOKENS_FILE', str(tmp_path / 'missing.json'))
    assert server.load_tokens() == {}


def test_http_abort_status_is_not_rewritten_as_internal_error():
    """Expected client errors retain their intended HTTP status."""
    response = server.app.test_client().get('/download')
    assert response.status_code == 400


def test_rejected_token_log_uses_non_secret_identifier(monkeypatch):
    """An unknown bearer token must not be persisted in request logs."""
    token = 'UnknownBearerToken_123'
    events = []
    monkeypatch.setattr(server, 'load_tokens', lambda: {})
    monkeypatch.setattr(server, 'log_event', events.append)

    response = server.app.test_client().get(f'/download?token={token}')

    assert response.status_code == 403
    assert len(events) == 1
    assert token not in events[0]
    assert server.utils.token_fingerprint(token) in events[0]


def test_download_fails_closed_when_registry_write_fails(monkeypatch, tmp_path):
    """A reusable on-disk token must not authorize a download after write failure."""
    token = 'ReusableToken_123'
    zips = tmp_path / 'zips'
    zips.mkdir()
    (zips / 'archive.zip').write_bytes(b'archive')
    events = []

    monkeypatch.setattr(server, 'ZIPS_DIR', str(zips))
    monkeypatch.setattr(server, 'load_tokens', lambda: {token: 'archive.zip'})
    monkeypatch.setattr(
        server, 'save_tokens', lambda _tokens: (_ for _ in ()).throw(OSError('read-only')),
    )
    monkeypatch.setattr(server, 'log_event', events.append)
    monkeypatch.setattr(server.utils, 'report_exception', lambda *_args: None)

    response = server.app.test_client().get(f'/download?token={token}')

    assert response.status_code == 500
    assert events == []
