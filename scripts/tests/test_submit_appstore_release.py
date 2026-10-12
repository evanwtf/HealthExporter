"""Tests for scripts/submit_appstore_release.py.

The App Store Connect API is a fake: httpx.MockTransport on an httpx.Client.
Every contact value here is fake. The repo is public.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

import httpx
import pytest

import asc_api
import submit_appstore_release as submit

APP_ID = "6759867648"

CONTACT_ENV = {
    "ASC_REVIEW_CONTACT_FIRST_NAME": "Ada",
    "ASC_REVIEW_CONTACT_LAST_NAME": "Example",
    "ASC_REVIEW_CONTACT_EMAIL": "reviewer@example.com",
    "ASC_REVIEW_CONTACT_PHONE": "+1 555 0100 123",
}
KEPT_CONTACT = {
    "contactFirstName": "Grace",
    "contactLastName": "Sample",
    "contactEmail": "kept@example.com",
    "contactPhone": "+1 555 0199 456",
}

CHANGELOG = (
    "# Changelog\n\nRelease notes for testers.\n\n"
    "## Unreleased\n\n"
    "## v2.5.5 (build 57), 2026-10-12\n\n"
    "- The export is faster.\n"
    "<!-- A note for developers: >60 stays in this comment. -->\n\n"
    "## v2.5.4 (build 56), 2026-10-11\n\n"
    "- Settings has a new close button.\n\n"
    "---\n\nFooter.\n"
)
CHANGELOG_NOTES = "- The export is faster."


# --- A fake App Store Connect -------------------------------------------------


def build(
    number: str = "57",
    train: str = "2.5.5",
    *,
    state: str = "VALID",
    expired: bool = False,
    encryption: bool | None = False,
    uploaded: str = "2026-10-12T10:00:00Z",
) -> dict[str, Any]:
    return {
        "number": number,
        "train": train,
        "state": state,
        "expired": expired,
        "encryption": encryption,
        "uploaded": uploaded,
    }


def localization(
    *,
    whats_new: str = "",
    description: str = "Export Health data to CSV.",
    keywords: str = "health,csv",
    support_url: str = "https://example.com/support",
    locale: str = "en-US",
) -> dict[str, Any]:
    return {
        "id": f"loc-{locale}",
        "attributes": {
            "locale": locale,
            "description": description,
            "keywords": keywords,
            "supportUrl": support_url,
            "whatsNew": whats_new,
        },
    }


class FakeASC:
    """Enough of the App Store Connect API for one release.

    Each request is logged as "METHOD path" in `calls`, in order.
    """

    def __init__(
        self,
        *,
        builds: list[dict[str, Any]] | None = None,
        versions: list[tuple[str, str, str]] | None = None,
        localizations: list[dict[str, Any]] | None = None,
        new_localizations: list[dict[str, Any]] | None = None,
        screenshots: list[str] | None = None,
        app_infos: list[tuple[str, str]] | None = None,
        privacy_url: str = "https://example.com/privacy",
        review_detail: dict[str, Any] | None = None,
        submissions: list[tuple[str, str]] | None = None,
        items: list[str] | None = None,
        fail: dict[str, tuple[int, str, str]] | None = None,
    ) -> None:
        self.builds = [build()] if builds is None else builds
        # (id, versionString, appVersionState)
        self.versions = (
            [("ver-1", "2.5.5", "PREPARE_FOR_SUBMISSION")]
            if versions is None
            else versions
        )
        self.localizations = (
            [localization()] if localizations is None else localizations
        )
        self.new_localizations = (
            [localization()] if new_localizations is None else new_localizations
        )
        self.screenshots = (
            ["COMPLETE", "COMPLETE"] if screenshots is None else screenshots
        )
        self.app_infos = (
            [
                ("info-live", "READY_FOR_DISTRIBUTION"),
                ("info-next", "PREPARE_FOR_SUBMISSION"),
            ]
            if app_infos is None
            else app_infos
        )
        self.privacy_url = privacy_url
        self.review_detail = review_detail
        self.submissions = [] if submissions is None else submissions
        self.items = [] if items is None else items
        self.fail = {} if fail is None else fail
        self.calls: list[str] = []
        self.params: dict[str, dict[str, str]] = {}
        self.bodies: dict[str, Any] = {}
        self.created_version = False

    def __call__(self, request: httpx.Request) -> httpx.Response:
        path = request.url.path.removeprefix("/v1")
        call = f"{request.method} {path}"
        self.calls.append(call)
        self.params[call] = dict(request.url.params)
        if request.content:
            self.bodies[call] = json.loads(request.content)
        if call in self.fail:
            status, title, detail = self.fail[call]
            return httpx.Response(
                status, json={"errors": [{"title": title, "detail": detail}]}
            )
        if request.method == "GET":
            return self.get(path)
        if call == "POST /appStoreVersions":
            self.created_version = True
            return httpx.Response(201, json={"data": {"id": "ver-new"}})
        if call == "POST /reviewSubmissions":
            return httpx.Response(201, json={"data": {"id": "sub-new"}})
        if call in ("POST /appStoreReviewDetails", "POST /reviewSubmissionItems"):
            return httpx.Response(201, json={"data": {"id": "created"}})
        if request.method == "PATCH" and path.endswith("/relationships/build"):
            return httpx.Response(204)
        if request.method == "PATCH":
            return httpx.Response(200, json={"data": {"id": path.rsplit("/", 1)[1]}})
        return httpx.Response(500, json={"errors": [{"detail": call}]})

    def get(self, path: str) -> httpx.Response:
        if path == "/apps":
            return ok([{"id": APP_ID}])
        if path == "/builds":
            return self.get_builds()
        if path == f"/apps/{APP_ID}/appStoreVersions":
            return ok(
                [
                    {
                        "id": vid,
                        "attributes": {"versionString": vs, "appVersionState": st},
                    }
                    for vid, vs, st in self.versions
                ]
            )
        if path.endswith("/appStoreVersionLocalizations"):
            if path.startswith("/appStoreVersions/ver-new/"):
                return ok(self.new_localizations)
            return ok(self.localizations)
        if path.endswith("/appScreenshotSets"):
            return ok([{"id": "set-1"}] if self.screenshots else [])
        if path == "/appScreenshotSets/set-1/appScreenshots":
            return ok(
                [
                    {
                        "id": f"shot-{n}",
                        "attributes": {
                            "fileName": f"0{n}.png",
                            "assetDeliveryState": {"state": state},
                        },
                    }
                    for n, state in enumerate(self.screenshots, start=1)
                ]
            )
        if path == f"/apps/{APP_ID}/appInfos":
            return ok(
                [{"id": i, "attributes": {"state": s}} for i, s in self.app_infos]
            )
        if path.startswith("/appInfos/") and path.endswith("/appInfoLocalizations"):
            info_id = path.split("/")[2]
            url = self.privacy_url if info_id != "info-live" else "https://live.example"
            return ok(
                [
                    {
                        "id": "il-1",
                        "attributes": {"locale": "en-US", "privacyPolicyUrl": url},
                    }
                ]
            )
        if path.endswith("/appStoreReviewDetail"):
            if self.review_detail is None:
                return httpx.Response(200, json={"data": None})
            return httpx.Response(
                200, json={"data": {"id": "rd-1", "attributes": self.review_detail}}
            )
        if path == "/reviewSubmissions":
            return ok(
                [
                    {"id": sid, "attributes": {"platform": "IOS", "state": st}}
                    for sid, st in self.submissions
                ]
            )
        if path.endswith("/items"):
            return ok(
                [
                    {
                        "id": f"item-{v}",
                        "relationships": {
                            "appStoreVersion": {
                                "data": {"type": "appStoreVersions", "id": v}
                            }
                        },
                    }
                    for v in self.items
                ]
            )
        return httpx.Response(404, json={"errors": [{"title": "Not found"}]})

    def get_builds(self) -> httpx.Response:
        params = self.params["GET /builds"]
        wanted_number = params.get("filter[version]")
        wanted_train = params.get("filter[preReleaseVersion.version]")
        data = []
        included = []
        for b in self.builds:
            if wanted_number is not None and b["number"] != wanted_number:
                continue
            if wanted_train is not None and b["train"] != wanted_train:
                continue
            train_id = f"train-{b['train']}"
            data.append(
                {
                    "id": f"build-{b['number']}",
                    "attributes": {
                        "version": b["number"],
                        "processingState": b["state"],
                        "expired": b["expired"],
                        "usesNonExemptEncryption": b["encryption"],
                        "uploadedDate": b["uploaded"],
                    },
                    "relationships": {
                        "preReleaseVersion": {
                            "data": {"type": "preReleaseVersions", "id": train_id}
                        }
                    },
                }
            )
            included.append(
                {
                    "type": "preReleaseVersions",
                    "id": train_id,
                    "attributes": {"version": b["train"], "platform": "IOS"},
                }
            )
        return httpx.Response(200, json={"data": data, "included": included})

    def client(self) -> httpx.Client:
        return httpx.Client(
            base_url=asc_api.ASC_BASE,
            headers={"Authorization": "Bearer test"},
            transport=httpx.MockTransport(self),
        )

    def writes(self) -> list[str]:
        return [c for c in self.calls if not c.startswith("GET ")]


def ok(data: list[dict[str, Any]]) -> httpx.Response:
    return httpx.Response(200, json={"data": data})


@pytest.fixture
def changelog_path(tmp_path: Path) -> Path:
    path = tmp_path / "changelog.md"
    path.write_text(CHANGELOG)
    return path


def call(
    fake: FakeASC,
    changelog_path: Path,
    *extra: str,
    env: dict[str, str] | None = None,
    version: str = "2.5.5",
) -> int:
    argv = ["--version", version, "--changelog", str(changelog_path), *extra]
    return submit.main(
        argv,
        client_factory=fake.client,
        env=CONTACT_ENV if env is None else env,
    )


def problems_logged(caplog: pytest.LogCaptureFixture) -> str:
    return "\n".join(
        r.getMessage() for r in caplog.records if r.levelno >= logging.ERROR
    )


PREPARE_WRITES = [
    "PATCH /appStoreVersions/ver-1",
    "PATCH /appStoreVersions/ver-1/relationships/build",
    "PATCH /appStoreVersionLocalizations/loc-en-US",
    "POST /appStoreReviewDetails",
]


# --- Modes --------------------------------------------------------------------


def test_dry_run_sends_only_get_requests(changelog_path: Path) -> None:
    fake = FakeASC()

    assert call(fake, changelog_path) == 0
    assert fake.writes() == []
    assert len(fake.calls) > 5


def test_dry_run_sends_only_gets_in_submit_shape(changelog_path: Path) -> None:
    fake = FakeASC(versions=[("ver-0", "2.5.4", "PREPARE_FOR_SUBMISSION")])

    assert call(fake, changelog_path, "--mode", "dry-run") == 0
    assert fake.writes() == []


def test_dry_run_exits_non_zero_on_a_problem(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC(screenshots=[])

    assert call(fake, changelog_path) == 1
    assert fake.writes() == []
    assert "screenshot set is empty" in problems_logged(caplog)


def test_prepare_writes_the_version_and_no_review_submission(
    changelog_path: Path,
) -> None:
    fake = FakeASC(submissions=[("sub-1", "READY_FOR_REVIEW")])

    assert call(fake, changelog_path, "--mode", "prepare") == 0
    assert fake.writes() == PREPARE_WRITES
    assert not any("reviewSubmission" in w for w in fake.writes())


def test_submit_sends_the_writes_in_order(changelog_path: Path) -> None:
    fake = FakeASC()

    assert call(fake, changelog_path, "--mode", "submit") == 0
    assert fake.writes() == [
        *PREPARE_WRITES,
        "POST /reviewSubmissions",
        "POST /reviewSubmissionItems",
        "PATCH /reviewSubmissions/sub-new",
    ]
    assert fake.bodies["PATCH /appStoreVersions/ver-1"]["data"]["attributes"] == {
        "releaseType": "AFTER_APPROVAL"
    }
    attach = fake.bodies["PATCH /appStoreVersions/ver-1/relationships/build"]
    assert attach == {"data": {"type": "builds", "id": "build-57"}}
    item = fake.bodies["POST /reviewSubmissionItems"]["data"]["relationships"]
    assert item["reviewSubmission"]["data"]["id"] == "sub-new"
    assert item["appStoreVersion"]["data"]["id"] == "ver-1"
    submitted = fake.bodies["PATCH /reviewSubmissions/sub-new"]["data"]
    assert submitted["attributes"] == {"submitted": True}
    created = fake.bodies["POST /reviewSubmissions"]["data"]
    assert created["attributes"] == {"platform": "IOS"}
    assert created["relationships"]["app"]["data"]["id"] == APP_ID


def test_submit_with_manual_release_type(changelog_path: Path) -> None:
    fake = FakeASC()

    assert (
        call(fake, changelog_path, "--mode", "submit", "--release-type", "manual") == 0
    )
    body = fake.bodies["PATCH /appStoreVersions/ver-1"]["data"]["attributes"]
    assert body == {"releaseType": "MANUAL"}


def test_parse_args_defaults() -> None:
    args = submit.parse_args(["--version", "2.5.5"])

    assert args.mode == "dry-run"
    assert args.release_type == "after-approval"
    assert args.locale == "en-US"
    assert args.build is None
    assert args.changelog == submit.REPO_ROOT / "docs" / "changelog.md"
    assert not args.replace_whats_new


@pytest.mark.parametrize(
    "argv",
    [
        ["--version", "v2.5.5"],
        ["--version", "2.5"],
        ["--version", "2.5.5", "--build", "57a"],
        ["--version", "2.5.5", "--build", "0"],
        ["--version", "2.5.5", "--mode", "upload"],
        ["--build", "57"],
    ],
)
def test_parse_args_refuses_bad_input(argv: list[str]) -> None:
    with pytest.raises(SystemExit):
        submit.parse_args(argv)


# --- Check 1: the build -------------------------------------------------------


def test_default_build_is_the_newest_valid_unexpired_build(
    changelog_path: Path,
) -> None:
    fake = FakeASC(
        builds=[
            build("55", uploaded="2026-10-10T00:00:00Z"),
            build("58", state="PROCESSING", uploaded="2026-10-12T12:00:00Z"),
            build("57", uploaded="2026-10-12T10:00:00Z"),
            build("59", expired=True, uploaded="2026-10-12T13:00:00Z"),
        ]
    )

    assert call(fake, changelog_path, "--mode", "prepare") == 0
    attach = fake.bodies["PATCH /appStoreVersions/ver-1/relationships/build"]
    assert attach["data"]["id"] == "build-57"
    assert fake.params["GET /builds"]["filter[preReleaseVersion.version]"] == "2.5.5"


def test_explicit_build_is_used(changelog_path: Path) -> None:
    fake = FakeASC(builds=[build("57"), build("56", uploaded="2026-10-11T00:00:00Z")])

    assert call(fake, changelog_path, "--build", "56", "--mode", "prepare") == 0
    attach = fake.bodies["PATCH /appStoreVersions/ver-1/relationships/build"]
    assert attach["data"]["id"] == "build-56"
    assert fake.params["GET /builds"]["filter[version]"] == "56"


@pytest.mark.parametrize(
    ("builds", "extra", "message"),
    [
        ([], ["--build", "57"], "No build 57"),
        ([], [], "No VALID, unexpired build for version 2.5.5"),
        ([build(state="PROCESSING")], [], "No VALID, unexpired build"),
        ([build(state="PROCESSING")], ["--build", "57"], "57 is PROCESSING, not VALID"),
        ([build(expired=True)], ["--build", "57"], "57 is expired"),
        ([build(encryption=None)], [], "no export compliance answer"),
        ([build(train="2.5.4")], ["--build", "57"], "57 is version 2.5.4, not 2.5.5"),
    ],
)
def test_build_refusals(
    changelog_path: Path,
    caplog: pytest.LogCaptureFixture,
    builds: list[dict[str, Any]],
    extra: list[str],
    message: str,
) -> None:
    fake = FakeASC(builds=builds)

    assert call(fake, changelog_path, "--mode", "submit", *extra) == 1
    assert message in problems_logged(caplog)
    assert fake.writes() == []


# --- Check 2: the App Store version -------------------------------------------


@pytest.mark.parametrize(
    "state",
    [
        "DEVELOPER_REJECTED",
        "REJECTED",
        "METADATA_REJECTED",
        "INVALID_BINARY",
        "READY_FOR_REVIEW",
    ],
)
def test_an_editable_version_is_reused(changelog_path: Path, state: str) -> None:
    fake = FakeASC(versions=[("ver-1", "2.5.5", state)])

    assert call(fake, changelog_path, "--mode", "prepare") == 0
    assert fake.writes() == PREPARE_WRITES


@pytest.mark.parametrize(
    "state", ["READY_FOR_DISTRIBUTION", "WAITING_FOR_REVIEW", "IN_REVIEW"]
)
def test_a_version_in_another_state_is_refused(
    changelog_path: Path, caplog: pytest.LogCaptureFixture, state: str
) -> None:
    fake = FakeASC(versions=[("ver-1", "2.5.5", state)])

    assert call(fake, changelog_path, "--mode", "submit") == 1
    assert f"2.5.5 is {state}" in problems_logged(caplog)
    assert fake.writes() == []


def test_a_lower_editable_version_is_renamed(changelog_path: Path) -> None:
    fake = FakeASC(
        versions=[
            ("ver-live", "2.4.7", "READY_FOR_DISTRIBUTION"),
            ("ver-1", "2.5.4", "PREPARE_FOR_SUBMISSION"),
        ]
    )

    assert call(fake, changelog_path, "--mode", "prepare") == 0
    assert fake.writes() == ["PATCH /appStoreVersions/ver-1", *PREPARE_WRITES]
    # One key holds the last body per call; the rename is the first PATCH.
    patches = [c for c in fake.calls if c == "PATCH /appStoreVersions/ver-1"]
    assert len(patches) == 2


def test_the_rename_sends_the_new_version_string(changelog_path: Path) -> None:
    fake = FakeASC(versions=[("ver-1", "2.5.4", "PREPARE_FOR_SUBMISSION")])
    bodies: list[Any] = []
    handler = fake.__call__

    def recording(request: httpx.Request) -> httpx.Response:
        if (
            request.method == "PATCH"
            and request.url.path == "/v1/appStoreVersions/ver-1"
        ):
            bodies.append(json.loads(request.content)["data"]["attributes"])
        return handler(request)

    def client() -> httpx.Client:
        return httpx.Client(
            base_url=asc_api.ASC_BASE, transport=httpx.MockTransport(recording)
        )

    argv = [
        "--version",
        "2.5.5",
        "--changelog",
        str(changelog_path),
        "--mode",
        "prepare",
    ]
    assert submit.main(argv, client_factory=client, env=CONTACT_ENV) == 0
    assert bodies == [{"versionString": "2.5.5"}, {"releaseType": "AFTER_APPROVAL"}]


def test_a_numerically_lower_version_is_renamed(changelog_path: Path) -> None:
    # As strings, "2.5.10" < "2.5.9". As numbers it is higher.
    fake = FakeASC(
        versions=[("ver-1", "2.5.9", "PREPARE_FOR_SUBMISSION")],
        builds=[build(train="2.5.10")],
    )
    text = CHANGELOG.replace("v2.5.5 (build 57)", "v2.5.10 (build 57)")
    changelog_path.write_text(text)

    assert call(fake, changelog_path, "--mode", "prepare", version="2.5.10") == 0
    assert fake.writes()[0] == "PATCH /appStoreVersions/ver-1"


def test_a_higher_editable_version_is_refused(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC(versions=[("ver-1", "2.6.0", "PREPARE_FOR_SUBMISSION")])

    assert call(fake, changelog_path, "--mode", "submit") == 1
    assert "App Store version 2.6.0 is editable" in problems_logged(caplog)
    assert fake.writes() == []


def test_a_rejected_other_version_is_refused(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC(versions=[("ver-1", "2.5.4", "REJECTED")])

    assert call(fake, changelog_path, "--mode", "submit") == 1
    assert "2.5.4 is editable (REJECTED)" in problems_logged(caplog)
    assert fake.writes() == []


def test_a_missing_version_is_created_then_checked(changelog_path: Path) -> None:
    fake = FakeASC(versions=[("ver-live", "2.4.7", "READY_FOR_DISTRIBUTION")])

    assert call(fake, changelog_path, "--mode", "submit") == 0
    assert fake.writes() == [
        "POST /appStoreVersions",
        "PATCH /appStoreVersions/ver-new/relationships/build",
        "PATCH /appStoreVersionLocalizations/loc-en-US",
        "POST /appStoreReviewDetails",
        "POST /reviewSubmissions",
        "POST /reviewSubmissionItems",
        "PATCH /reviewSubmissions/sub-new",
    ]
    created = fake.bodies["POST /appStoreVersions"]["data"]
    assert created["attributes"] == {
        "platform": "IOS",
        "versionString": "2.5.5",
        "releaseType": "AFTER_APPROVAL",
    }
    # The checks of the new version ran after the create.
    create_at = fake.calls.index("POST /appStoreVersions")
    assert (
        "GET /appStoreVersions/ver-new/appStoreVersionLocalizations"
        in fake.calls[create_at:]
    )


def test_dry_run_of_a_missing_version_defers_the_version_checks(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC(versions=[])
    caplog.set_level(logging.INFO)

    assert call(fake, changelog_path) == 0
    assert fake.writes() == []
    assert not any("appStoreVersionLocalizations" in c for c in fake.calls)
    assert "checks run after the create" in caplog.text


def test_dry_run_of_a_missing_version_checks_the_changelog(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC(versions=[])

    assert call(fake, changelog_path, version="2.5.6") == 1
    assert "v2.5.6 has no section" in problems_logged(caplog)


def test_a_created_version_that_fails_a_check_stops_the_writes(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC(versions=[], new_localizations=[localization(keywords="")])

    assert call(fake, changelog_path, "--mode", "submit") == 1
    assert fake.writes() == ["POST /appStoreVersions"]
    logged = problems_logged(caplog)
    assert "Created version 2.5.5 (id ver-new)" in logged
    assert "The en-US keywords is empty" in logged


# --- Check 3: the localization ------------------------------------------------


@pytest.mark.parametrize(
    ("fields", "message"),
    [
        ({"description": ""}, "en-US description is empty"),
        ({"keywords": "  "}, "en-US keywords is empty"),
        ({"support_url": ""}, "en-US supportUrl is empty"),
    ],
)
def test_localization_refusals(
    changelog_path: Path,
    caplog: pytest.LogCaptureFixture,
    fields: dict[str, str],
    message: str,
) -> None:
    fake = FakeASC(localizations=[localization(**fields)])

    assert call(fake, changelog_path, "--mode", "submit") == 1
    assert message in problems_logged(caplog)
    assert fake.writes() == []


def test_a_missing_locale_is_refused(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC(localizations=[localization(locale="de-DE")])

    assert call(fake, changelog_path, "--mode", "submit") == 1
    assert "no en-US localization" in problems_logged(caplog)


# --- Check 4: What's New ------------------------------------------------------


def whats_new_body(fake: FakeASC) -> Any:
    body = fake.bodies.get("PATCH /appStoreVersionLocalizations/loc-en-US")
    return None if body is None else body["data"]["attributes"]["whatsNew"]


def test_whats_new_comes_from_the_changelog_when_empty(changelog_path: Path) -> None:
    fake = FakeASC()

    assert call(fake, changelog_path, "--mode", "prepare") == 0
    # The developer comment, with its ">", is not in the text.
    assert whats_new_body(fake) == CHANGELOG_NOTES


def test_whats_new_is_kept_when_set(changelog_path: Path) -> None:
    fake = FakeASC(localizations=[localization(whats_new="Bug fixes.")])

    assert call(fake, changelog_path, "--mode", "prepare") == 0
    assert whats_new_body(fake) is None
    assert "PATCH /appStoreVersionLocalizations/loc-en-US" not in fake.writes()


def test_kept_whats_new_needs_no_changelog_section(changelog_path: Path) -> None:
    changelog_path.write_text(
        CHANGELOG.replace("v2.5.5 (build 57)", "v2.5.6 (build 57)")
    )
    fake = FakeASC(localizations=[localization(whats_new="Bug fixes.")])

    assert call(fake, changelog_path, "--mode", "prepare") == 0


def test_replace_whats_new_uses_the_changelog(changelog_path: Path) -> None:
    fake = FakeASC(localizations=[localization(whats_new="Bug fixes.")])

    assert call(fake, changelog_path, "--mode", "prepare", "--replace-whats-new") == 0
    assert whats_new_body(fake) == CHANGELOG_NOTES


def test_replace_whats_new_with_the_same_text_writes_nothing(
    changelog_path: Path,
) -> None:
    fake = FakeASC(localizations=[localization(whats_new=CHANGELOG_NOTES)])

    assert call(fake, changelog_path, "--mode", "prepare", "--replace-whats-new") == 0
    assert whats_new_body(fake) is None


def test_whats_new_refuses_markup(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    changelog_path.write_text(
        CHANGELOG.replace("- The export is faster.", "- A value >60 is kept.")
    )
    fake = FakeASC()

    assert call(fake, changelog_path, "--mode", "submit") == 1
    assert "markup" in problems_logged(caplog)
    assert fake.writes() == []


def test_whats_new_refuses_more_than_4000_characters(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    changelog_path.write_text(
        CHANGELOG.replace("- The export is faster.", "- " + "a" * 4000)
    )
    fake = FakeASC()

    assert call(fake, changelog_path, "--mode", "submit") == 1
    assert "4000" in problems_logged(caplog)
    assert fake.writes() == []


def test_whats_new_refuses_a_missing_section(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    changelog_path.write_text(
        CHANGELOG.replace("v2.5.5 (build 57)", "v2.5.6 (build 57)")
    )
    fake = FakeASC()

    assert call(fake, changelog_path, "--mode", "submit") == 1
    assert "v2.5.5 has no section" in problems_logged(caplog)


@pytest.mark.parametrize(
    ("text", "message"),
    [
        ("", "empty"),
        ("   \n", "empty"),
        ("a" * 4001, "4001 characters"),
        ("Use <b>bold</b>.", "'<' and '>'"),
        ("More than >60.", "'>'"),
    ],
)
def test_whats_new_problems(text: str, message: str) -> None:
    assert message in " ".join(submit.whats_new_problems(text))


def test_whats_new_problems_accepts_4000_plain_characters() -> None:
    assert submit.whats_new_problems("a" * 4000) == []


# --- Check 5: the screenshots -------------------------------------------------


@pytest.mark.parametrize(
    ("screenshots", "message"),
    [
        ([], "APP_IPHONE_67 screenshot set is empty"),
        (["COMPLETE", "UPLOAD_COMPLETE"], "02.png is UPLOAD_COMPLETE, not COMPLETE"),
        (["FAILED"], "01.png is FAILED"),
    ],
)
def test_screenshot_refusals(
    changelog_path: Path,
    caplog: pytest.LogCaptureFixture,
    screenshots: list[str],
    message: str,
) -> None:
    fake = FakeASC(screenshots=screenshots)

    assert call(fake, changelog_path, "--mode", "submit") == 1
    assert message in problems_logged(caplog)
    assert fake.writes() == []


# --- Check 6: the privacy policy ----------------------------------------------


def test_the_editable_app_info_is_checked(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC(privacy_url="")

    assert call(fake, changelog_path, "--mode", "submit") == 1
    assert "en-US privacy policy URL is empty" in problems_logged(caplog)
    assert "GET /appInfos/info-next/appInfoLocalizations" in fake.calls


def test_the_live_app_info_is_the_fallback(changelog_path: Path) -> None:
    fake = FakeASC(app_infos=[("info-live", "READY_FOR_DISTRIBUTION")], privacy_url="")

    assert call(fake, changelog_path) == 0
    assert "GET /appInfos/info-live/appInfoLocalizations" in fake.calls


@pytest.mark.parametrize(
    ("infos", "picked"),
    [
        ([("a", "READY_FOR_DISTRIBUTION"), ("b", "PREPARE_FOR_SUBMISSION")], "b"),
        ([("a", "REPLACED_WITH_NEW_INFO"), ("b", "WAITING_FOR_REVIEW")], "b"),
        ([("a", "WAITING_FOR_REVIEW"), ("b", "REJECTED")], "b"),
        ([("a", "READY_FOR_DISTRIBUTION")], "a"),
    ],
)
def test_pick_app_info(infos: list[tuple[str, str]], picked: str) -> None:
    resources = [{"id": i, "attributes": {"state": s}} for i, s in infos]

    chosen = submit.pick_app_info(resources)

    assert chosen is not None
    assert chosen["id"] == picked


def test_pick_app_info_reads_the_older_state_attribute() -> None:
    resources = [
        {"id": "a", "attributes": {"appStoreState": "READY_FOR_SALE"}},
        {"id": "b", "attributes": {"appStoreState": "PREPARE_FOR_SUBMISSION"}},
    ]

    chosen = submit.pick_app_info(resources)

    assert chosen is not None
    assert chosen["id"] == "b"


def test_no_app_info_is_refused(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC(app_infos=[])

    assert call(fake, changelog_path) == 1
    assert "no app information" in problems_logged(caplog)


# --- Check 7: the App Review contact ------------------------------------------


def review_attributes(fake: FakeASC) -> Any:
    for key in ("POST /appStoreReviewDetails", "PATCH /appStoreReviewDetails/rd-1"):
        if key in fake.bodies:
            return fake.bodies[key]["data"]["attributes"]
    return None


def test_a_new_review_detail_is_created_from_the_secrets(changelog_path: Path) -> None:
    fake = FakeASC()

    assert call(fake, changelog_path, "--mode", "prepare") == 0
    body = fake.bodies["POST /appStoreReviewDetails"]["data"]
    assert body["attributes"] == {
        "contactFirstName": "Ada",
        "contactLastName": "Example",
        "contactEmail": "reviewer@example.com",
        "contactPhone": "+1 555 0100 123",
        "demoAccountRequired": False,
    }
    assert body["relationships"]["appStoreVersion"]["data"]["id"] == "ver-1"


def test_the_secrets_win_over_app_store_connect(changelog_path: Path) -> None:
    fake = FakeASC(review_detail={**KEPT_CONTACT, "demoAccountRequired": False})

    assert call(fake, changelog_path, "--mode", "prepare") == 0
    assert fake.writes()[-1] == "PATCH /appStoreReviewDetails/rd-1"
    assert review_attributes(fake) == {
        "contactFirstName": "Ada",
        "contactLastName": "Example",
        "contactEmail": "reviewer@example.com",
        "contactPhone": "+1 555 0100 123",
    }


def test_app_store_connect_values_are_kept_without_secrets(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC(review_detail={**KEPT_CONTACT, "demoAccountRequired": None})
    caplog.set_level(logging.INFO)

    assert call(fake, changelog_path, "--mode", "prepare", env={}) == 0
    # A kept value is not sent again.
    assert review_attributes(fake) == {"demoAccountRequired": False}
    assert "App Review contact phone: kept" in caplog.text


def test_kept_values_and_a_set_demo_flag_send_no_review_detail(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC(review_detail={**KEPT_CONTACT, "demoAccountRequired": False})
    caplog.set_level(logging.INFO)

    assert call(fake, changelog_path, "--mode", "prepare", env={}) == 0
    assert not any("appStoreReviewDetails" in w for w in fake.writes())
    assert "App Review contact: no change" in caplog.text


def test_one_secret_and_three_kept_values(changelog_path: Path) -> None:
    fake = FakeASC(review_detail=dict(KEPT_CONTACT))
    env = {"ASC_REVIEW_CONTACT_PHONE": "+44 20 7946 0000"}

    assert call(fake, changelog_path, "--mode", "prepare", env=env) == 0
    assert review_attributes(fake) == {
        "contactPhone": "+44 20 7946 0000",
        "demoAccountRequired": False,
    }


def test_a_missing_contact_names_the_secret(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC()
    env = {k: v for k, v in CONTACT_ENV.items() if k != "ASC_REVIEW_CONTACT_PHONE"}

    assert call(fake, changelog_path, "--mode", "submit", env=env) == 1
    assert "Set the secret ASC_REVIEW_CONTACT_PHONE" in problems_logged(caplog)
    assert fake.writes() == []


def test_every_missing_contact_is_reported(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC()

    assert call(fake, changelog_path, env={}) == 1
    logged = problems_logged(caplog)
    for name in CONTACT_ENV:
        assert name in logged


def test_a_404_review_detail_counts_as_none(changelog_path: Path) -> None:
    fake = FakeASC(
        fail={
            "GET /appStoreVersions/ver-1/appStoreReviewDetail": (
                404,
                "Not found",
                "There is no resource.",
            )
        }
    )

    assert call(fake, changelog_path, "--mode", "prepare") == 0
    assert "POST /appStoreReviewDetails" in fake.writes()


@pytest.mark.parametrize(
    "phone",
    ["+1 (555) 010-0123", "+44.20.7946.0000", "+15550100123"],
)
def test_valid_phone(phone: str) -> None:
    assert submit.valid_phone(phone)


@pytest.mark.parametrize(
    "phone",
    ["555 0100 123", "+1 555 01", "+1 555 0100 ext 5", "+", "1-555-0100-123"],
)
def test_invalid_phone(phone: str) -> None:
    assert not submit.valid_phone(phone)


@pytest.mark.parametrize("email", ["reviewer@example.com", "a.b@mail.example.org"])
def test_valid_email(email: str) -> None:
    assert submit.valid_email(email)


@pytest.mark.parametrize(
    "email",
    [
        "reviewer",
        "a@b@example.com",
        "reviewer@example",
        "@example.com",
        "a b@x.com",
        "a@.com",
        "a@example.",
    ],
)
def test_invalid_email(email: str) -> None:
    assert not submit.valid_email(email)


def test_an_invalid_phone_is_refused_without_its_value(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC()
    env = {**CONTACT_ENV, "ASC_REVIEW_CONTACT_PHONE": "555 0100 999"}

    assert call(fake, changelog_path, "--mode", "submit", env=env) == 1
    logged = problems_logged(caplog)
    assert "contact phone (set from secret) is not valid" in logged
    assert "555 0100 999" not in caplog.text


def test_an_invalid_email_is_refused_without_its_value(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC()
    env = {**CONTACT_ENV, "ASC_REVIEW_CONTACT_EMAIL": "nobody-at-example"}

    assert call(fake, changelog_path, "--mode", "submit", env=env) == 1
    assert "contact email (set from secret) is not an email" in problems_logged(caplog)
    assert "nobody-at-example" not in caplog.text


def test_no_contact_value_appears_in_any_log_record(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.DEBUG)
    fake = FakeASC()

    assert call(fake, changelog_path, "--mode", "submit") == 0
    assert "PATCH /reviewSubmissions/sub-new" in fake.writes()
    text = "\n".join(
        [r.getMessage() for r in caplog.records] + [str(r.args) for r in caplog.records]
    )
    for value in CONTACT_ENV.values():
        assert value not in text
    assert "App Review contact email: set from secret" in text


def test_an_api_error_that_echoes_a_contact_value_is_redacted(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC(
        fail={
            "POST /appStoreReviewDetails": (
                409,
                "The provided entity includes an attribute with an invalid value",
                "contactEmail 'reviewer@example.com' is not valid",
            )
        }
    )

    assert call(fake, changelog_path, "--mode", "submit") == 1
    logged = problems_logged(caplog)
    assert "invalid value" in logged
    assert "contactEmail '[redacted]' is not valid" in logged
    assert "reviewer@example.com" not in caplog.text
    assert not any("reviewSubmission" in w for w in fake.writes())


# --- Check 8: the review submissions ------------------------------------------


@pytest.mark.parametrize("state", ["WAITING_FOR_REVIEW", "IN_REVIEW"])
def test_a_submission_in_review_is_refused(
    changelog_path: Path, caplog: pytest.LogCaptureFixture, state: str
) -> None:
    fake = FakeASC(submissions=[("sub-1", state)])

    assert call(fake, changelog_path, "--mode", "submit") == 1
    assert f"sub-1 is already in review ({state})" in problems_logged(caplog)
    assert fake.writes() == []


def test_a_rejected_submission_asks_for_an_answer(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC(submissions=[("sub-1", "UNRESOLVED_ISSUES")])

    assert call(fake, changelog_path, "--mode", "submit") == 1
    logged = problems_logged(caplog)
    assert "sub-1 has unresolved issues" in logged
    assert "Answer App Review in App Store Connect" in logged
    assert fake.writes() == []


def test_a_submission_in_review_also_blocks_prepare(changelog_path: Path) -> None:
    fake = FakeASC(submissions=[("sub-1", "IN_REVIEW")])

    assert call(fake, changelog_path, "--mode", "prepare") == 1
    assert fake.writes() == []


def test_a_ready_for_review_submission_is_reused(changelog_path: Path) -> None:
    fake = FakeASC(submissions=[("sub-1", "READY_FOR_REVIEW")])

    assert call(fake, changelog_path, "--mode", "submit") == 0
    assert fake.writes() == [
        *PREPARE_WRITES,
        "POST /reviewSubmissionItems",
        "PATCH /reviewSubmissions/sub-1",
    ]


def test_a_version_already_in_the_submission_is_not_added_again(
    changelog_path: Path,
) -> None:
    fake = FakeASC(submissions=[("sub-1", "READY_FOR_REVIEW")], items=["ver-1"])

    assert call(fake, changelog_path, "--mode", "submit") == 0
    assert fake.writes() == [*PREPARE_WRITES, "PATCH /reviewSubmissions/sub-1"]


def test_a_failed_submit_run_can_run_again(changelog_path: Path) -> None:
    # The first run added the version to the draft, then failed. The version is
    # READY_FOR_REVIEW. The second run reuses both and submits.
    fake = FakeASC(
        versions=[("ver-1", "2.5.5", "READY_FOR_REVIEW")],
        submissions=[("sub-1", "READY_FOR_REVIEW")],
        items=["ver-1"],
    )

    assert call(fake, changelog_path, "--mode", "submit") == 0
    assert fake.writes() == [*PREPARE_WRITES, "PATCH /reviewSubmissions/sub-1"]


def test_dry_run_logs_the_submission_plan(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC(submissions=[("sub-1", "READY_FOR_REVIEW")])
    caplog.set_level(logging.INFO)

    assert call(fake, changelog_path) == 0
    assert "Review submission in mode submit: reuse sub-1" in caplog.text
    assert "GET /reviewSubmissions/sub-1/items" in fake.calls
    assert fake.writes() == []


def test_the_submission_query_asks_for_open_ios_submissions(
    changelog_path: Path,
) -> None:
    fake = FakeASC()

    call(fake, changelog_path)

    params = fake.params["GET /reviewSubmissions"]
    assert params["filter[app]"] == APP_ID
    assert params["filter[platform]"] == "IOS"
    assert set(params["filter[state]"].split(",")) == {
        "READY_FOR_REVIEW",
        "WAITING_FOR_REVIEW",
        "IN_REVIEW",
        "UNRESOLVED_ISSUES",
    }


# --- Every problem at once, and API errors ------------------------------------


def test_every_problem_is_reported_at_once(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC(
        builds=[build(encryption=None)],
        screenshots=["FAILED"],
        privacy_url="",
        submissions=[("sub-1", "IN_REVIEW")],
        localizations=[localization(description="")],
    )

    assert call(fake, changelog_path, "--mode", "submit", env={}) == 1
    logged = problems_logged(caplog)
    for message in (
        "no export compliance answer",
        "description is empty",
        "01.png is FAILED",
        "privacy policy URL is empty",
        "ASC_REVIEW_CONTACT_FIRST_NAME",
        "already in review",
    ):
        assert message in logged
    assert fake.writes() == []


def test_an_api_error_logs_its_title_and_detail(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC(
        fail={
            "PATCH /appStoreVersions/ver-1/relationships/build": (
                409,
                "The build is not valid",
                "The build is already attached to another version.",
            )
        }
    )

    assert call(fake, changelog_path, "--mode", "submit") == 1
    logged = problems_logged(caplog)
    assert "Attach build 57: HTTP 409" in logged
    assert "The build is not valid: The build is already attached" in logged
    assert "POST /appStoreReviewDetails" not in fake.writes()


def test_a_read_error_is_reported(
    changelog_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    fake = FakeASC(fail={"GET /builds": (403, "Forbidden", "The key has no access.")})

    assert call(fake, changelog_path) == 1
    assert "List the builds: HTTP 403. Forbidden: The key has no access." in (
        problems_logged(caplog)
    )


def test_main_fails_without_credentials(
    changelog_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    for name in ("ASC_API_KEY_ID", "ASC_API_ISSUER_ID", "ASC_API_KEY_P8"):
        monkeypatch.delenv(name, raising=False)

    status = submit.main(
        ["--version", "2.5.5", "--changelog", str(changelog_path)], env=CONTACT_ENV
    )

    assert status == 1
