"""Tests for scripts/asc_api.py."""

from __future__ import annotations

from pathlib import Path

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

import asc_api


@pytest.fixture
def private_key_pem() -> str:
    key = ec.generate_private_key(ec.SECP256R1())
    return key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode()


def test_build_jwt_signs_an_asc_token(private_key_pem: str) -> None:
    token = asc_api.build_jwt("KEY123", "issuer-uuid", private_key_pem, now=1000)

    header = jwt.get_unverified_header(token)
    claims = jwt.decode(token, options={"verify_signature": False})
    assert header["alg"] == "ES256"
    assert header["kid"] == "KEY123"
    assert claims == {
        "iss": "issuer-uuid",
        "iat": 1000,
        "exp": 1000 + 15 * 60,
        "aud": "appstoreconnect-v1",
    }


def test_load_private_key_accepts_inline_pem(private_key_pem: str) -> None:
    assert asc_api.load_private_key(private_key_pem) == private_key_pem


def test_load_private_key_reads_a_file(private_key_pem: str, tmp_path: Path) -> None:
    path = tmp_path / "AuthKey_KEY123.p8"
    path.write_text(private_key_pem)

    assert asc_api.load_private_key(str(path)) == private_key_pem


def test_load_private_key_does_not_echo_a_bad_value(tmp_path: Path) -> None:
    secret_looking = "not-a-key-but-do-not-print-me"

    with pytest.raises(asc_api.ASCError) as excinfo:
        asc_api.load_private_key(secret_looking)

    assert secret_looking not in str(excinfo.value)


def test_require_env_rejects_an_empty_value(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ASC_API_KEY_ID", "")

    with pytest.raises(asc_api.ASCError, match="ASC_API_KEY_ID"):
        asc_api.require_env("ASC_API_KEY_ID")


def test_bundle_id_defaults_to_healthexporter(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ASC_BUNDLE_ID", "")

    assert asc_api.bundle_id_from_env() == "com.evanhoffman.HealthExporter"


def test_get_app_id_raises_for_an_unknown_bundle() -> None:
    client = httpx.Client(
        base_url=asc_api.ASC_BASE,
        transport=httpx.MockTransport(
            lambda request: httpx.Response(200, json={"data": []})
        ),
    )

    with pytest.raises(asc_api.ASCError, match=r"com\.example\.Nope"):
        asc_api.get_app_id(client, "com.example.Nope")
