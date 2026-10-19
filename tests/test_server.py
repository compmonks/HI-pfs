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
