import importlib
import os
import sys
import types

# Ensure the project root is on sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

# Create a minimal Flask stub so that scripts.server can be imported without Flask installed
flask_stub = types.ModuleType('flask')

class DummyFlask:
    def __init__(self, *args, **kwargs):
        pass

    def route(self, *args, **kwargs):
        def decorator(func):
            return func
        return decorator

flask_stub.Flask = DummyFlask
flask_stub.request = types.SimpleNamespace(remote_addr='127.0.0.1')
flask_stub.send_file = lambda *a, **kw: None
flask_stub.abort = lambda *a, **kw: None
sys.modules.setdefault('flask', flask_stub)

server = importlib.import_module('scripts.server')


def test_valid_token_returns_match():
    token = 'ValidToken_123-abc'
    assert server.sanitize_token(token) is not None


def test_invalid_token_space_returns_none():
    assert server.sanitize_token('invalid token') is None


def test_invalid_token_special_char_returns_none():
    assert server.sanitize_token('invalid$token') is None
