"""Tests for scripts/promote_testflight_external.py."""

from __future__ import annotations

import json
from typing import Any

import httpx
import pytest

import asc_api
import promote_testflight_external as promote

INTERNAL = {
    "id": "g-internal",
    "attributes": {"name": "Internal", "isInternalGroup": True},
}
HOFFGROUP = {
    "id": "g-hoff",
    "attributes": {"name": "External Hoffgroup", "isInternalGroup": False},
}
OTHER = {
    "id": "g-other",
    "attributes": {"name": "Other external", "isInternalGroup": False},
}


def build(state: str = "VALID", expired: bool = False) -> dict[str, Any]:
    return {
        "id": "b-57",
        "attributes": {"version": "57", "processingState": state, "expired": expired},
    }


class FakeASC:
    def __init__(
        self,
        build: dict[str, Any],
        groups: list[dict[str, Any]],
        submit_status: int = 201,
        add_status: int = 204,
    ) -> None:
        self.build = build
        self.groups = groups
        self.submit_status = submit_status
        self.add_status = add_status
        self.writes: list[tuple[str, dict[str, Any]]] = []
        self.build_params: httpx.QueryParams | None = None

    def __call__(self, request: httpx.Request) -> httpx.Response:
        path = request.url.path
        if request.method == "GET" and path == "/v1/apps":
            return httpx.Response(200, json={"data": [{"id": "6759867648"}]})
        if request.method == "GET" and path == "/v1/builds":
            self.build_params = request.url.params
            return httpx.Response(200, json={"data": [self.build]})
        if request.method == "GET" and path == "/v1/betaGroups":
            return httpx.Response(200, json={"data": self.groups})
        self.writes.append((path, json.loads(request.content)))
        if path == "/v1/betaAppReviewSubmissions":
            return httpx.Response(self.submit_status, json={})
        return httpx.Response(self.add_status)

    def client(self) -> httpx.Client:
        return httpx.Client(
            base_url=asc_api.ASC_BASE, transport=httpx.MockTransport(self)
        )


def test_select_groups_defaults_to_every_external_group() -> None:
    targets = promote.select_groups([INTERNAL, HOFFGROUP, OTHER], [])

    assert [g["id"] for g in targets] == ["g-hoff", "g-other"]


def test_select_groups_matches_a_name_without_case() -> None:
    targets = promote.select_groups(
        [INTERNAL, HOFFGROUP, OTHER], ["external hoffgroup"]
    )

    assert [g["id"] for g in targets] == ["g-hoff"]


def test_select_groups_never_picks_an_internal_group() -> None:
    with pytest.raises(asc_api.ASCError, match="internal"):
        promote.select_groups([INTERNAL, HOFFGROUP], ["Internal"])


def test_select_groups_fails_on_an_unknown_name() -> None:
    with pytest.raises(asc_api.ASCError, match="no such group"):
        promote.select_groups([HOFFGROUP], ["No such group"])


def test_select_groups_fails_with_no_external_group() -> None:
    with pytest.raises(asc_api.ASCError, match="No external beta group"):
        promote.select_groups([INTERNAL], [])


@pytest.mark.parametrize(
    ("state", "expired", "message"),
    [("PROCESSING", False, "not VALID"), ("VALID", True, "expired")],
)
def test_check_promotable_refuses_a_build(
    state: str, expired: bool, message: str
) -> None:
    with pytest.raises(asc_api.ASCError, match=message):
        promote.check_promotable(build(state, expired))


def test_run_adds_the_build_and_submits_it() -> None:
    fake = FakeASC(build(), [INTERNAL, HOFFGROUP])

    promote.run(fake.client(), promote.parse_args(["--build", "57"]))

    assert fake.build_params is not None
    assert fake.build_params["filter[version]"] == "57"
    assert fake.writes == [
        (
            "/v1/betaGroups/g-hoff/relationships/builds",
            {"data": [{"type": "builds", "id": "b-57"}]},
        ),
        (
            "/v1/betaAppReviewSubmissions",
            {
                "data": {
                    "type": "betaAppReviewSubmissions",
                    "relationships": {
                        "build": {"data": {"type": "builds", "id": "b-57"}}
                    },
                }
            },
        ),
    ]


def test_run_with_no_submit_only_adds_the_build() -> None:
    fake = FakeASC(build(), [HOFFGROUP])

    promote.run(fake.client(), promote.parse_args(["--build", "57", "--no-submit"]))

    assert [path for path, _ in fake.writes] == [
        "/v1/betaGroups/g-hoff/relationships/builds"
    ]


def test_run_with_inspect_changes_nothing() -> None:
    fake = FakeASC(build("PROCESSING"), [HOFFGROUP])

    promote.run(fake.client(), promote.parse_args(["--build", "57", "--inspect"]))

    assert fake.writes == []


def test_run_accepts_an_existing_review_submission() -> None:
    fake = FakeASC(build(), [HOFFGROUP], submit_status=409)

    promote.run(fake.client(), promote.parse_args(["--build", "57"]))

    assert len(fake.writes) == 2


def test_run_fails_when_the_submission_fails() -> None:
    fake = FakeASC(build(), [HOFFGROUP], submit_status=500)

    with pytest.raises(asc_api.ASCError, match="beta review"):
        promote.run(fake.client(), promote.parse_args(["--build", "57"]))


def test_run_fails_when_adding_to_a_group_fails() -> None:
    fake = FakeASC(build(), [HOFFGROUP], add_status=403)

    with pytest.raises(asc_api.ASCError, match="g-hoff"):
        promote.run(fake.client(), promote.parse_args(["--build", "57"]))


def test_run_refuses_a_build_that_is_still_processing() -> None:
    fake = FakeASC(build("PROCESSING"), [HOFFGROUP])

    with pytest.raises(asc_api.ASCError, match="not VALID"):
        promote.run(fake.client(), promote.parse_args(["--build", "57"]))
    assert fake.writes == []


def test_main_fails_without_credentials(monkeypatch: pytest.MonkeyPatch) -> None:
    for name in ("ASC_API_KEY_ID", "ASC_API_ISSUER_ID", "ASC_API_KEY_P8"):
        monkeypatch.delenv(name, raising=False)

    assert promote.main(["--build", "57"]) == 1
