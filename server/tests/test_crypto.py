"""Encryption-at-rest round-trip (encrypt -> "restart" -> decrypt)."""

from __future__ import annotations

import pytest
from cryptography.fernet import InvalidToken

from vesnai.crypto import MAGIC, decrypt_blob, encrypt_blob


def test_encrypt_decrypt_round_trip():
    data = b"the user's private knowledge bundle" * 100
    blob = encrypt_blob(data, "correct horse battery staple")
    assert blob.startswith(MAGIC)
    assert data not in blob  # ciphertext does not leak plaintext
    assert decrypt_blob(blob, "correct horse battery staple") == data


def test_wrong_passphrase_fails():
    blob = encrypt_blob(b"secret", "right")
    with pytest.raises(InvalidToken):
        decrypt_blob(blob, "wrong")


def test_rejects_non_encrypted_blob():
    with pytest.raises(ValueError):
        decrypt_blob(b"PK\x03\x04 plain zip", "x")
