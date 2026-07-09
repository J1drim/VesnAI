"""Encryption-at-rest for backups/exports.

A passphrase-derived key (PBKDF2-HMAC-SHA256) wraps a Fernet token, so an
exported bundle can be encrypted and only restored with the same passphrase.
Used for the optional encrypted-backup UX; the in-place bundle can also be kept
on an encrypted volume.
"""

from __future__ import annotations

import base64
import os

from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

MAGIC = b"VESNAIENC1"
_SALT_LEN = 16
_ITERATIONS = 390_000


def _derive_key(passphrase: str, salt: bytes) -> bytes:
    kdf = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=salt, iterations=_ITERATIONS)
    return base64.urlsafe_b64encode(kdf.derive(passphrase.encode()))


def encrypt_blob(data: bytes, passphrase: str) -> bytes:
    salt = os.urandom(_SALT_LEN)
    token = Fernet(_derive_key(passphrase, salt)).encrypt(data)
    return MAGIC + salt + token


def decrypt_blob(blob: bytes, passphrase: str) -> bytes:
    if not blob.startswith(MAGIC):
        raise ValueError("not a VesnAI encrypted backup")
    salt = blob[len(MAGIC) : len(MAGIC) + _SALT_LEN]
    token = blob[len(MAGIC) + _SALT_LEN :]
    return Fernet(_derive_key(passphrase, salt)).decrypt(token)
