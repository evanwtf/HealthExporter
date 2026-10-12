"""Tests for scripts/update_testflight_notes.py (ported from StationCast)."""

from __future__ import annotations

import argparse
import json
from collections.abc import Callable
from typing import Any

import httpx
import pytest

import asc_api
import update_testflight_notes as notes

Handler = Callable[[httpx.Request], httpx.Response]


def build_response(build_id: str, number: str, train: str) -> dict[str, Any]:
    return {
        "data": [
            {
                "type": "builds",
                "id": build_id,
                "attributes": {
                    "version": number,
                    "uploadedDate": "2026-10-06T08:45:00-04:00",
                },
                "relationships": {
                    "preReleaseVersion": {
                        "data": {"type": "preReleaseVersions", "id": f"train-{train}"}
                    }
                },
            }
        ],
        "included": [
            {
                "type": "preReleaseVersions",
                "id": f"train-{train}",
                "attributes": {"version": train},
            }
        ],
    }


def mock_client(handler: Handler) -> httpx.Client:
    return httpx.Client(
        base_url=asc_api.ASC_BASE, transport=httpx.MockTransport(handler)
    )


def client_returning(body: dict[str, Any], seen: list[httpx.Request]) -> httpx.Client:
    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=body)

    return mock_client(handler)


def test_get_build_filters_on_the_build_number_and_the_app_version() -> None:
    seen: list[httpx.Request] = []
    client = client_returning(build_response("new-57", "57", "2.5.5"), seen)

    build = notes.get_build(client, "app-1", "57", app_version="2.5.5")

    assert build["id"] == "new-57"
    params = seen[0].url.params
    assert seen[0].url.path == "/v1/builds"
    assert params["filter[version]"] == "57"
    assert params["filter[preReleaseVersion.version]"] == "2.5.5"
    assert params["include"] == "preReleaseVersion"


def test_get_build_refuses_a_build_from_another_version() -> None:
    # Before ASC lists the new upload, an older version's build 57 comes back.
    client = client_returning(build_response("old-57", "57", "2.5.4"), [])

    with pytest.raises(asc_api.ASCError, match=r"2\.5\.4"):
        notes.get_build(client, "app-1", "57", app_version="2.5.5")


def test_get_build_refuses_a_build_with_no_version() -> None:
    body = build_response("odd-57", "57", "2.5.5")
    body["included"] = []
    client = client_returning(body, [])

    with pytest.raises(asc_api.ASCError, match=r"2\.5\.5"):
        notes.get_build(client, "app-1", "57", app_version="2.5.5")


def test_get_build_raises_while_the_new_build_is_not_listed_yet() -> None:
    # The workflow retries on this error until ASC lists the upload.
    client = client_returning({"data": [], "included": []}, [])

    with pytest.raises(asc_api.ASCError, match="No build found"):
        notes.get_build(client, "app-1", "57", app_version="2.5.5")


def test_get_build_without_an_app_version_keeps_the_plain_query() -> None:
    seen: list[httpx.Request] = []
    client = client_returning(build_response("any-57", "57", "2.5.4"), seen)

    build = notes.get_build(client, "app-1", "57")

    assert build["id"] == "any-57"
    params = seen[0].url.params
    assert "filter[preReleaseVersion.version]" not in params
    assert "include" not in params


def test_parse_args_accepts_an_app_version() -> None:
    args = notes.parse_args(["--build", "57", "--app-version", "2.5.5"])

    assert args.app_version == "2.5.5"


def test_parse_args_defaults_to_the_healthexporter_bundle(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("ASC_BUNDLE_ID", raising=False)

    args = notes.parse_args(["--build", "57"])

    assert args.bundle_id == "com.evanhoffman.HealthExporter"


class FakeASC:
    """Answers the four calls a notes update makes."""

    def __init__(self, existing_notes: str | None) -> None:
        self.existing_notes = existing_notes
        self.writes: list[tuple[str, str, dict[str, Any]]] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        path = request.url.path
        if request.method == "GET" and path == "/v1/apps":
            assert request.url.params["filter[bundleId]"] == (
                "com.evanhoffman.HealthExporter"
            )
            return httpx.Response(200, json={"data": [{"id": "6759867648"}]})
        if request.method == "GET" and path == "/v1/builds":
            return httpx.Response(200, json=build_response("b-57", "57", "2.5.5"))
        if request.method == "GET" and path.endswith("/betaBuildLocalizations"):
            data = []
            if self.existing_notes is not None:
                data.append(
                    {
                        "id": "loc-1",
                        "attributes": {
                            "locale": "en-US",
                            "whatsNew": self.existing_notes,
                        },
                    }
                )
            return httpx.Response(200, json={"data": data})
        body = json.loads(request.content)
        self.writes.append((request.method, path, body))
        return httpx.Response(200, json={"data": {"id": "loc-1"}})


def run_args() -> argparse.Namespace:
    return notes.parse_args(
        [
            "--build",
            "57",
            "--app-version",
            "2.5.5",
            "--bundle-id",
            "com.evanhoffman.HealthExporter",
            "--locale",
            "en-US",
        ]
    )


def test_run_creates_the_localization_when_none_exists() -> None:
    fake = FakeASC(existing_notes=None)

    notes.run(mock_client(fake), run_args(), "Try the Cancel button.")

    [(method, path, body)] = fake.writes
    assert (method, path) == ("POST", "/v1/betaBuildLocalizations")
    assert body["data"]["attributes"] == {
        "locale": "en-US",
        "whatsNew": "Try the Cancel button.",
    }
    assert body["data"]["relationships"]["build"]["data"]["id"] == "b-57"


def test_run_updates_an_existing_localization() -> None:
    fake = FakeASC(existing_notes="Old notes")

    notes.run(mock_client(fake), run_args(), "New notes")

    [(method, path, body)] = fake.writes
    assert (method, path) == ("PATCH", "/v1/betaBuildLocalizations/loc-1")
    assert body["data"]["attributes"] == {"whatsNew": "New notes"}


def test_run_without_notes_writes_nothing() -> None:
    fake = FakeASC(existing_notes="Old notes")

    notes.run(mock_client(fake), run_args(), None)

    assert fake.writes == []


def test_main_fails_without_credentials(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    for name in ("ASC_API_KEY_ID", "ASC_API_ISSUER_ID", "ASC_API_KEY_P8"):
        monkeypatch.delenv(name, raising=False)

    assert notes.main(["--build", "57", "--notes", "x"]) == 1
