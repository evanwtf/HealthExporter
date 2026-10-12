"""App Store Connect API helpers shared by the TestFlight scripts.

Authentication uses the team API key as an ES256 JWT. The environment
variables match the CI workflows:

    ASC_API_KEY_ID     App Store Connect API key identifier
    ASC_API_ISSUER_ID  ASC issuer identifier (UUID)
    ASC_API_KEY_P8     EITHER a path to AuthKey_<KEY_ID>.p8 OR the inline PEM

Optional:
    ASC_BUNDLE_ID      Bundle identifier (default: com.evanhoffman.HealthExporter)
"""

from __future__ import annotations

import logging
import os
import sys
import time
from pathlib import Path
from typing import Any, cast

import httpx
import jwt

ASC_BASE = "https://api.appstoreconnect.apple.com/v1"
# HealthExporter is App Store Connect app 6759867648. The scripts look the app
# up by bundle ID, so the same key works for the team's other apps.
DEFAULT_BUNDLE_ID = "com.evanhoffman.HealthExporter"
# ASC tokens may live up to 20 minutes; use a conservative 15.
TOKEN_TTL_SECONDS = 15 * 60

JSONObject = dict[str, Any]

# App Store version states in which the metadata, the screenshots and the
# build can change.
EDITABLE_VERSION_STATES = frozenset(
    {
        "PREPARE_FOR_SUBMISSION",
        "DEVELOPER_REJECTED",
        "REJECTED",
        "METADATA_REJECTED",
        "INVALID_BINARY",
    }
)


def configure_logging() -> None:
    """Log to stdout, and keep httpx and httpcore quiet.

    httpx logs each request URL at INFO. The screenshot upload URLs are
    pre-signed, so a logged URL is a credential. Keep these loggers at WARNING.
    """
    logging.basicConfig(
        level=logging.INFO,
        stream=sys.stdout,
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
    )
    for name in ("httpx", "httpcore"):
        logging.getLogger(name).setLevel(logging.WARNING)


class ASCError(Exception):
    """App Store Connect returned no usable answer."""


def build_jwt(
    key_id: str, issuer_id: str, private_key_pem: str, now: int | None = None
) -> str:
    issued = int(time.time()) if now is None else now
    payload = {
        "iss": issuer_id,
        "iat": issued,
        "exp": issued + TOKEN_TTL_SECONDS,
        "aud": "appstoreconnect-v1",
    }
    headers = {"kid": key_id, "typ": "JWT"}
    return jwt.encode(payload, private_key_pem, algorithm="ES256", headers=headers)


def load_private_key(value: str) -> str:
    """Accept either an inline PEM string or a path to a .p8 file."""
    # Any PEM block marks an inline key; a path never contains one.
    if "-----BEGIN " in value:
        return value
    path = Path(value).expanduser()
    if not path.is_file():
        # Never echo the value: it can be a mangled key.
        raise ASCError("ASC_API_KEY_P8 is neither an inline PEM nor an existing file")
    return path.read_text()


def require_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise ASCError(f"Missing required environment variable: {name}")
    return value


def client_from_env() -> httpx.Client:
    """An httpx client for the ASC API, authenticated from the environment."""
    key_id = require_env("ASC_API_KEY_ID")
    issuer_id = require_env("ASC_API_ISSUER_ID")
    private_key = load_private_key(require_env("ASC_API_KEY_P8"))
    token = build_jwt(key_id, issuer_id, private_key)
    return httpx.Client(
        base_url=ASC_BASE,
        headers={"Authorization": f"Bearer {token}"},
        timeout=60.0,
    )


def bundle_id_from_env() -> str:
    return os.environ.get("ASC_BUNDLE_ID") or DEFAULT_BUNDLE_ID


def data_list(response: httpx.Response) -> list[JSONObject]:
    """The `data` array of a JSON:API response."""
    response.raise_for_status()
    return cast(list[JSONObject], response.json().get("data", []))


def data_object(response: httpx.Response) -> JSONObject:
    """The `data` object of a JSON:API response."""
    response.raise_for_status()
    return cast(JSONObject, response.json()["data"])


def get_app_id(client: httpx.Client, bundle_id: str) -> str:
    data = data_list(
        client.get("/apps", params={"filter[bundleId]": bundle_id, "limit": 1})
    )
    if not data:
        raise ASCError(f"No app found in App Store Connect for bundleId={bundle_id}")
    return str(data[0]["id"])


def version_state(version: JSONObject) -> str | None:
    """The state of an App Store version. Older responses use appStoreState."""
    attrs = version.get("attributes", {})
    state = attrs.get("appVersionState") or attrs.get("appStoreState")
    return None if state is None else str(state)
