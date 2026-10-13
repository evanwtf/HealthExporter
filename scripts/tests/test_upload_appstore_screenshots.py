"""Tests for scripts/upload_appstore_screenshots.py (ported from StationCast).

The App Store Connect API is a fake: httpx.MockTransport on an httpx.Client.
"""

from __future__ import annotations

import hashlib
import json
import logging
import struct
import zlib
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import httpx
import pytest

import asc_api
import upload_appstore_screenshots as shots

APPROVED = [
    "01-launch-light",
    "08-data-selection-mixed-light",
    "09-lab-panel-detail-light",
    "10-export-history-light",
    "08-data-selection-mixed-dark",
    "04-privacy-light",
]
REPO_ROOT = Path(__file__).resolve().parents[2]


def chunk(kind: bytes, body: bytes) -> bytes:
    crc = zlib.crc32(kind + body)
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", crc)


def png(
    width: int = 1320,
    height: int = 2868,
    *,
    color_type: int = 2,
    trns: bool = False,
) -> bytes:
    """A small PNG: the signature, IHDR, an optional tRNS, IDAT and IEND.

    The IDAT is not a real image. The reader stops at IDAT and never decodes.
    """
    ihdr = struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0)
    body = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
    if trns:
        body += chunk(b"tRNS", b"\x00\x00\x00\x00\x00\x00")
    return body + chunk(b"IDAT", zlib.compress(b"\x00")) + chunk(b"IEND", b"")


def write_set(folder: Path, names: list[str], data: bytes | None = None) -> None:
    for name in names:
        (folder / f"{name}.png").write_bytes(png() if data is None else data)


# --- parse_manifest ---------------------------------------------------------


def test_parse_manifest_keeps_the_order_and_skips_comments_and_blanks() -> None:
    text = (
        "# The approved set, in store order.\n"
        "\n"
        "01-launch-light\n"
        "  08-data-selection-mixed-light   # the hero\n"
        "\n"
        "# 03-settings-light\n"
        "04-privacy-light\n"
    )

    assert shots.parse_manifest(text) == [
        "01-launch-light",
        "08-data-selection-mixed-light",
        "04-privacy-light",
    ]


def test_parse_manifest_refuses_an_empty_manifest() -> None:
    with pytest.raises(shots.ScreenshotError, match="no screenshot names"):
        shots.parse_manifest("# nothing approved yet\n\n")


def test_parse_manifest_refuses_a_name_listed_twice() -> None:
    with pytest.raises(shots.ScreenshotError, match=r"01-launch-light.*twice"):
        shots.parse_manifest("01-launch-light\n04-privacy-light\n01-launch-light\n")


@pytest.mark.parametrize("name", ["01-launch-light.png", "dark/01-launch", ".."])
def test_parse_manifest_refuses_a_file_name_or_a_path(name: str) -> None:
    with pytest.raises(shots.ScreenshotError, match=r"line 1"):
        shots.parse_manifest(f"{name}\n")


def test_the_repo_manifest_is_the_approved_set() -> None:
    manifest = REPO_ROOT / "ci" / "appstore-screenshots.txt"

    assert shots.parse_manifest(manifest.read_text()) == APPROVED


# --- read_png_header --------------------------------------------------------


def test_read_png_header_reads_the_size_of_an_opaque_image() -> None:
    header = shots.read_png_header(png(1320, 2868, color_type=2))

    assert header == shots.PngHeader(width=1320, height=2868, has_alpha=False)


@pytest.mark.parametrize("color_type", [4, 6])
def test_read_png_header_finds_an_alpha_color_type(color_type: int) -> None:
    header = shots.read_png_header(png(1206, 2622, color_type=color_type))

    assert header.has_alpha
    assert (header.width, header.height) == (1206, 2622)


@pytest.mark.parametrize("color_type", [0, 2, 3])
def test_read_png_header_finds_a_transparency_chunk(color_type: int) -> None:
    assert shots.read_png_header(png(color_type=color_type, trns=True)).has_alpha


def test_read_png_header_ignores_chunks_after_the_image_data() -> None:
    data = png() + chunk(b"tRNS", b"\x00\x00")

    assert not shots.read_png_header(data).has_alpha


@pytest.mark.parametrize(
    "data",
    [b"\xff\xd8\xff\xe0 a JPEG", b"", b"\x89PNG\r\n\x1a\n" + chunk(b"IDAT", b"")],
)
def test_read_png_header_refuses_a_file_that_is_not_a_png(data: bytes) -> None:
    with pytest.raises(shots.ScreenshotError, match="not a PNG"):
        shots.read_png_header(data)


def test_read_png_header_refuses_a_truncated_file() -> None:
    with pytest.raises(shots.ScreenshotError, match="not a PNG"):
        shots.read_png_header(png()[:20])


# --- display_type -----------------------------------------------------------


@pytest.mark.parametrize("size", [(1320, 2868), (1290, 2796)])
def test_display_type_maps_the_six_point_nine_inch_sizes(
    size: tuple[int, int],
) -> None:
    assert shots.display_type(*size) == "APP_IPHONE_67"


@pytest.mark.parametrize("size", [(2868, 1320), (1206, 2622), (1179, 2556)])
def test_display_type_refuses_a_size_with_no_slot(size: tuple[int, int]) -> None:
    with pytest.raises(shots.ScreenshotError, match=f"{size[0]} x {size[1]}"):
        shots.display_type(*size)


# --- build_plan: the refusals before any write ------------------------------


def test_build_plan_keeps_the_manifest_order(tmp_path: Path) -> None:
    write_set(tmp_path, [*APPROVED, "03-settings-light"])

    plan = shots.build_plan(tmp_path, APPROVED)

    assert plan.display_type == "APP_IPHONE_67"
    assert [s.path.name for s in plan.screenshots] == [f"{n}.png" for n in APPROVED]


def test_build_plan_refuses_a_name_with_no_file(tmp_path: Path) -> None:
    write_set(tmp_path, APPROVED[:-1])

    with pytest.raises(shots.ScreenshotError, match=r"04-privacy-light.png: no file"):
        shots.build_plan(tmp_path, APPROVED)


def test_build_plan_refuses_a_size_with_no_slot(tmp_path: Path) -> None:
    write_set(tmp_path, APPROVED)
    (tmp_path / "04-privacy-light.png").write_bytes(png(1206, 2622))

    with pytest.raises(shots.ScreenshotError, match=r"04-privacy-light.*1206 x 2622"):
        shots.build_plan(tmp_path, APPROVED)


def test_build_plan_refuses_an_image_with_alpha(tmp_path: Path) -> None:
    write_set(tmp_path, APPROVED)
    (tmp_path / "01-launch-light.png").write_bytes(png(color_type=6))

    with pytest.raises(shots.ScreenshotError, match=r"01-launch-light.*alpha"):
        shots.build_plan(tmp_path, APPROVED)


def test_build_plan_reports_both_the_size_and_the_alpha(tmp_path: Path) -> None:
    # The old CI images: a 6.3-inch size, with alpha.
    write_set(tmp_path, APPROVED, png(1206, 2622, color_type=6))

    with pytest.raises(shots.ScreenshotError) as caught:
        shots.build_plan(tmp_path, APPROVED)

    message = str(caught.value)
    assert "01-launch-light.png: 1206 x 2622 has no App Store slot" in message
    assert "01-launch-light.png: alpha channel" in message


def test_build_plan_refuses_a_file_that_is_not_a_png(tmp_path: Path) -> None:
    write_set(tmp_path, APPROVED)
    (tmp_path / "01-launch-light.png").write_bytes(b"\xff\xd8\xff\xe0")

    with pytest.raises(shots.ScreenshotError, match=r"01-launch-light.*not a PNG"):
        shots.build_plan(tmp_path, APPROVED)


def test_build_plan_refuses_images_of_more_than_one_display_type(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    # Today every accepted size is one slot. Add an iPad size for the test.
    sizes = {**shots.DISPLAY_TYPES, (2064, 2752): "APP_IPAD_PRO_3GEN_129"}
    monkeypatch.setattr(shots, "DISPLAY_TYPES", sizes)
    write_set(tmp_path, APPROVED)
    (tmp_path / "04-privacy-light.png").write_bytes(png(2064, 2752))

    with pytest.raises(shots.ScreenshotError, match="more than one display type"):
        shots.build_plan(tmp_path, APPROVED)


def test_build_plan_refuses_more_than_ten_images(tmp_path: Path) -> None:
    names = [f"{i:02d}-screen" for i in range(11)]
    write_set(tmp_path, names)

    with pytest.raises(shots.ScreenshotError, match="11 screenshots; the limit is 10"):
        shots.build_plan(tmp_path, names)


def test_build_plan_accepts_ten_images(tmp_path: Path) -> None:
    names = [f"{i:02d}-screen" for i in range(10)]
    write_set(tmp_path, names)

    assert len(shots.build_plan(tmp_path, names).screenshots) == 10


def test_build_plan_reports_every_problem_at_once(tmp_path: Path) -> None:
    write_set(tmp_path, APPROVED[:3])
    (tmp_path / "01-launch-light.png").write_bytes(png(color_type=6))

    with pytest.raises(shots.ScreenshotError) as caught:
        shots.build_plan(tmp_path, APPROVED)

    message = str(caught.value)
    assert "01-launch-light.png: alpha" in message
    assert "08-data-selection-mixed-dark.png: no file" in message
    assert "04-privacy-light.png: no file" in message


# --- slices -----------------------------------------------------------------


def test_slices_cut_the_file_at_each_operation() -> None:
    data = bytes(range(10))
    ops = [{"offset": 0, "length": 4}, {"offset": 4, "length": 6}]

    assert shots.slices(data, ops) == [bytes(range(4)), bytes(range(4, 10))]


@pytest.mark.parametrize(
    "ops",
    [
        [{"offset": 0, "length": 4}, {"offset": 5, "length": 5}],
        [{"offset": 0, "length": 8}],
        [],
    ],
)
def test_slices_refuse_operations_that_do_not_cover_the_file(
    ops: list[dict[str, Any]],
) -> None:
    with pytest.raises(asc_api.ASCError, match="cover"):
        shots.slices(bytes(10), ops)


# --- A fake App Store Connect ----------------------------------------------


class FakeASC:
    """Enough of the App Store Connect API for one screenshot upload.

    Each request is logged as "METHOD path" in `calls`, in order. The upload
    PUTs go to a second fake, as the real pre-signed URLs do.
    """

    def __init__(
        self,
        *,
        versions: list[dict[str, Any]] | None = None,
        locales: tuple[str, ...] = ("en-US",),
        existing_set: bool = True,
        old_shots: tuple[str, ...] = ("old-1", "old-2"),
        delivery: list[str] | None = None,
    ) -> None:
        self.versions = (
            [version_resource("PREPARE_FOR_SUBMISSION")]
            if versions is None
            else versions
        )
        self.locales = locales
        self.existing_set = existing_set
        self.old_shots = old_shots
        # The delivery states each GET of a new screenshot returns, in turn.
        self.delivery = (
            ["UPLOAD_COMPLETE", "COMPLETE"] if delivery is None else delivery
        )
        self.polls: dict[str, int] = {}
        self.calls: list[str] = []
        self.bodies: dict[str, Any] = {}
        self.put_bodies: list[bytes] = []
        self.put_headers: list[httpx.Headers] = []
        self.created = 0

    def __call__(self, request: httpx.Request) -> httpx.Response:
        path = request.url.path.removeprefix("/v1")
        call = f"{request.method} {path}"
        self.calls.append(call)
        if request.content:
            self.bodies[call] = json.loads(request.content)
        if request.method == "GET":
            return self.get(path)
        if call == "POST /appScreenshotSets":
            return httpx.Response(201, json={"data": {"id": "set-new"}})
        if call == "POST /appScreenshots":
            return self.reserve(json.loads(request.content))
        if request.method == "PATCH" and path.startswith("/appScreenshots/"):
            return httpx.Response(200, json={"data": {"id": path.rsplit("/", 1)[1]}})
        if request.method in ("DELETE", "PATCH"):
            return httpx.Response(204)
        return httpx.Response(500, json={"errors": [{"detail": call}]})

    def get(self, path: str) -> httpx.Response:
        if path == "/apps":
            return httpx.Response(200, json={"data": [{"id": "6759867648"}]})
        if path == "/apps/6759867648/appStoreVersions":
            return httpx.Response(200, json={"data": self.versions})
        if path == "/appStoreVersions/ver-1/appStoreVersionLocalizations":
            data = [
                {"id": f"loc-{loc}", "attributes": {"locale": loc}}
                for loc in self.locales
            ]
            return httpx.Response(200, json={"data": data})
        if path == "/appStoreVersionLocalizations/loc-en-US/appScreenshotSets":
            data = [{"id": "set-1"}] if self.existing_set else []
            return httpx.Response(200, json={"data": data})
        if path == "/appScreenshotSets/set-1/appScreenshots":
            data = [
                {"id": i, "attributes": {"fileName": f"{i}.png"}}
                for i in self.old_shots
            ]
            return httpx.Response(200, json={"data": data})
        if path.startswith("/appScreenshots/"):
            shot_id = path.rsplit("/", 1)[1]
            poll = self.polls.get(shot_id, 0)
            self.polls[shot_id] = poll + 1
            state = self.delivery[min(poll, len(self.delivery) - 1)]
            attrs = {"assetDeliveryState": {"state": state, "errors": []}}
            return httpx.Response(200, json={"data": {"attributes": attrs}})
        return httpx.Response(404, json={"errors": [{"detail": path}]})

    def reserve(self, body: dict[str, Any]) -> httpx.Response:
        self.created += 1
        size = body["data"]["attributes"]["fileSize"]
        operations = [
            {
                "method": "PUT",
                "url": f"https://upload.example/{self.created}",
                "offset": 0,
                "length": size,
                "requestHeaders": [{"name": "Content-Type", "value": "image/png"}],
            }
        ]
        return httpx.Response(
            201,
            json={
                "data": {
                    "id": f"new-{self.created}",
                    "attributes": {"uploadOperations": operations},
                }
            },
        )

    def upload(self, request: httpx.Request) -> httpx.Response:
        self.calls.append(f"PUT {request.url}")
        self.put_bodies.append(request.content)
        self.put_headers.append(request.headers)
        return httpx.Response(200)

    def client(self) -> httpx.Client:
        return httpx.Client(
            base_url=asc_api.ASC_BASE,
            headers={"Authorization": "Bearer test"},
            transport=httpx.MockTransport(self),
        )

    def uploader(self) -> httpx.Client:
        return httpx.Client(transport=httpx.MockTransport(self.upload))

    def writes(self) -> list[str]:
        return [c for c in self.calls if not c.startswith("GET ")]


def version_resource(state: str) -> dict[str, Any]:
    return {
        "id": "ver-1",
        "attributes": {"versionString": "2.5.5", "appVersionState": state},
    }


def no_sleep(_: float) -> None:
    return None


@pytest.fixture
def approved_dir(tmp_path: Path) -> Path:
    # Each file differs, so the test can tell the uploads apart.
    for index, name in enumerate(APPROVED):
        (tmp_path / f"{name}.png").write_bytes(png() + bytes([index]))
    return tmp_path


def run(fake: FakeASC, folder: Path, *extra: str, version: str = "2.5.5") -> list[str]:
    args = shots.parse_args(["--version", version, "--source-dir", str(folder), *extra])
    plan = shots.build_plan(folder, APPROVED)
    shots.run(fake.client(), fake.uploader(), args, plan, sleep=no_sleep)
    return fake.writes()


# --- find_version and find_localization: the remote refusals ----------------


def test_run_refuses_a_version_that_does_not_exist(approved_dir: Path) -> None:
    fake = FakeASC(versions=[])

    with pytest.raises(asc_api.ASCError, match=r"No App Store version 2.5.5"):
        run(fake, approved_dir)
    assert fake.writes() == []


@pytest.mark.parametrize(
    "state", ["READY_FOR_DISTRIBUTION", "WAITING_FOR_REVIEW", "IN_REVIEW"]
)
def test_run_refuses_a_version_that_is_not_editable(
    approved_dir: Path, state: str
) -> None:
    fake = FakeASC(versions=[version_resource(state)])

    with pytest.raises(asc_api.ASCError, match=f"2.5.5 is {state}"):
        run(fake, approved_dir)
    assert fake.writes() == []


def test_find_version_reads_the_older_state_attribute() -> None:
    old = {"id": "ver-1", "attributes": {"appStoreState": "READY_FOR_SALE"}}
    fake = FakeASC(versions=[old])

    with pytest.raises(asc_api.ASCError, match="READY_FOR_SALE"):
        shots.find_version(fake.client(), "6759867648", "2.5.5")


@pytest.mark.parametrize(
    "state",
    [
        "PREPARE_FOR_SUBMISSION",
        "DEVELOPER_REJECTED",
        "REJECTED",
        "METADATA_REJECTED",
        "INVALID_BINARY",
    ],
)
def test_find_version_accepts_each_editable_state(state: str) -> None:
    fake = FakeASC(versions=[version_resource(state)])

    assert shots.find_version(fake.client(), "6759867648", "2.5.5")["id"] == "ver-1"


def test_run_refuses_a_locale_with_no_localization(approved_dir: Path) -> None:
    fake = FakeASC(locales=("de-DE",))

    with pytest.raises(asc_api.ASCError, match="No 'en-US' localization"):
        run(fake, approved_dir)
    assert fake.writes() == []


def test_run_uses_the_locale_argument(approved_dir: Path) -> None:
    fake = FakeASC(locales=("de-DE",))

    with pytest.raises(asc_api.ASCError, match="No 'fr-FR' localization"):
        run(fake, approved_dir, "--locale", "fr-FR")


# --- run: the upload --------------------------------------------------------


def test_run_replaces_the_set_in_manifest_order(approved_dir: Path) -> None:
    fake = FakeASC()

    writes = run(fake, approved_dir)

    expected = [
        "DELETE /appScreenshots/old-1",
        "DELETE /appScreenshots/old-2",
    ]
    for n in range(1, len(APPROVED) + 1):
        expected += [
            "POST /appScreenshots",
            f"PUT https://upload.example/{n}",
            f"PATCH /appScreenshots/new-{n}",
        ]
    expected.append("PATCH /appScreenshotSets/set-1/relationships/appScreenshots")
    assert writes == expected

    order = fake.bodies[expected[-1]]["data"]
    assert [entry["id"] for entry in order] == [
        f"new-{n}" for n in range(1, len(APPROVED) + 1)
    ]
    assert fake.put_bodies == [
        (approved_dir / f"{name}.png").read_bytes() for name in APPROVED
    ]


def test_run_waits_for_each_delivery_before_the_next_upload(
    approved_dir: Path,
) -> None:
    fake = FakeASC()

    run(fake, approved_dir)

    # Each new screenshot is polled until COMPLETE before the next reserve.
    first_commit = fake.calls.index("PATCH /appScreenshots/new-1")
    second_reserve = [
        i for i, c in enumerate(fake.calls) if c == "POST /appScreenshots"
    ][1]
    between = fake.calls[first_commit + 1 : second_reserve]
    assert between == ["GET /appScreenshots/new-1", "GET /appScreenshots/new-1"]
    assert fake.polls == {f"new-{n}": 2 for n in range(1, len(APPROVED) + 1)}


def test_run_creates_the_set_when_the_slot_is_empty(approved_dir: Path) -> None:
    fake = FakeASC(existing_set=False)

    writes = run(fake, approved_dir)

    assert writes[0] == "POST /appScreenshotSets"
    created = fake.bodies["POST /appScreenshotSets"]["data"]
    assert created["attributes"] == {"screenshotDisplayType": "APP_IPHONE_67"}
    localization = created["relationships"]["appStoreVersionLocalization"]["data"]
    assert localization["id"] == "loc-en-US"
    assert not any(c.startswith("DELETE") for c in writes)
    assert writes[-1] == (
        "PATCH /appScreenshotSets/set-new/relationships/appScreenshots"
    )


def test_run_with_dry_run_writes_nothing(approved_dir: Path) -> None:
    fake = FakeASC()

    assert run(fake, approved_dir, "--dry-run") == []
    assert fake.put_bodies == []


def test_run_with_dry_run_on_an_empty_slot_creates_no_set(approved_dir: Path) -> None:
    fake = FakeASC(existing_set=False)

    assert run(fake, approved_dir, "--dry-run") == []


def test_run_with_dry_run_still_refuses_a_locked_version(approved_dir: Path) -> None:
    fake = FakeASC(versions=[version_resource("READY_FOR_DISTRIBUTION")])

    with pytest.raises(asc_api.ASCError, match="READY_FOR_DISTRIBUTION"):
        run(fake, approved_dir, "--dry-run")


def test_run_stops_when_apple_rejects_a_screenshot(approved_dir: Path) -> None:
    fake = FakeASC(delivery=["FAILED"])

    with pytest.raises(asc_api.ASCError, match=r"rejected 01-launch-light.png"):
        run(fake, approved_dir)
    # No second upload and no reorder after a failure.
    assert fake.writes()[-1] == "PATCH /appScreenshots/new-1"


# --- upload_one and wait_until_delivered ------------------------------------


def test_upload_one_reserves_puts_and_commits_with_the_md5(tmp_path: Path) -> None:
    body = png()
    path = tmp_path / "01-launch-light.png"
    path.write_bytes(body)
    fake = FakeASC()

    shot_id = shots.upload_one(fake.client(), fake.uploader(), "set-1", path)

    assert shot_id == "new-1"
    assert fake.calls == [
        "POST /appScreenshots",
        "PUT https://upload.example/1",
        "PATCH /appScreenshots/new-1",
    ]
    reserved = fake.bodies["POST /appScreenshots"]["data"]
    assert reserved["attributes"] == {
        "fileName": "01-launch-light.png",
        "fileSize": len(body),
    }
    assert reserved["relationships"]["appScreenshotSet"]["data"]["id"] == "set-1"
    assert fake.put_bodies == [body]
    assert fake.put_headers[0]["Content-Type"] == "image/png"
    # The upload URL is pre-signed: the API token must not go there.
    assert "Authorization" not in fake.put_headers[0]
    committed = fake.bodies["PATCH /appScreenshots/new-1"]["data"]["attributes"]
    assert committed == {
        "uploaded": True,
        "sourceFileChecksum": hashlib.md5(body).hexdigest(),
    }


def test_upload_one_refuses_an_operation_that_is_not_put(tmp_path: Path) -> None:
    path = tmp_path / "01.png"
    path.write_bytes(png())

    def handler(request: httpx.Request) -> httpx.Response:
        ops: list[dict[str, Any]] = [
            {"method": "POST", "url": "https://x", "offset": 0, "length": 1}
        ]
        return httpx.Response(
            201, json={"data": {"id": "s", "attributes": {"uploadOperations": ops}}}
        )

    client = httpx.Client(
        base_url=asc_api.ASC_BASE, transport=httpx.MockTransport(handler)
    )

    with pytest.raises(asc_api.ASCError, match="POST"):
        shots.upload_one(client, client, "set-1", path)


def test_wait_until_delivered_times_out() -> None:
    fake = FakeASC(delivery=["UPLOAD_COMPLETE"])
    ticks = iter(range(0, 10_000, 100))

    with pytest.raises(asc_api.ASCError, match="still UPLOAD_COMPLETE"):
        shots.wait_until_delivered(
            fake.client(),
            "new-1",
            "01.png",
            sleep=no_sleep,
            clock=lambda: float(next(ticks)),
        )


# --- main -------------------------------------------------------------------


def unreachable_client() -> httpx.Client:
    raise AssertionError("a local refusal must come before any network call")


def test_main_refuses_a_bad_set_before_it_builds_a_client(tmp_path: Path) -> None:
    manifest = tmp_path / "manifest.txt"
    manifest.write_text("01-launch-light\n")
    (tmp_path / "01-launch-light.png").write_bytes(png(1206, 2622, color_type=6))

    status = shots.main(
        [
            "--version",
            "2.5.5",
            "--source-dir",
            str(tmp_path),
            "--manifest",
            str(manifest),
        ],
        client_factory=unreachable_client,
    )

    assert status == 1


def test_main_refuses_a_missing_manifest(tmp_path: Path) -> None:
    status = shots.main(
        [
            "--version",
            "2.5.5",
            "--source-dir",
            str(tmp_path),
            "--manifest",
            str(tmp_path / "absent.txt"),
        ],
        client_factory=unreachable_client,
    )

    assert status == 1


def test_main_refuses_a_malformed_version(tmp_path: Path) -> None:
    with pytest.raises(SystemExit):
        shots.parse_args(["--version", "v2.5.5", "--source-dir", str(tmp_path)])


def test_main_dry_run_reads_the_repo_manifest(approved_dir: Path) -> None:
    fake = FakeASC()

    status = shots.main(
        ["--version", "2.5.5", "--source-dir", str(approved_dir), "--dry-run"],
        client_factory=fake.client,
        uploader_factory=fake.uploader,
    )

    assert status == 0
    assert fake.writes() == []


def test_main_fails_without_credentials(
    approved_dir: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    for name in ("ASC_API_KEY_ID", "ASC_API_ISSUER_ID", "ASC_API_KEY_P8"):
        monkeypatch.delenv(name, raising=False)

    assert shots.main(["--version", "2.5.5", "--source-dir", str(approved_dir)]) == 1


# --- httpx logging stays off ------------------------------------------------


@pytest.fixture
def http_loggers() -> Iterator[None]:
    names = ("httpx", "httpcore")
    saved = {name: logging.getLogger(name).level for name in names}
    yield
    for name, level in saved.items():
        logging.getLogger(name).setLevel(level)


@pytest.mark.usefixtures("http_loggers")
def test_configure_logging_raises_httpx_to_warning() -> None:
    logging.getLogger("httpx").setLevel(logging.INFO)
    logging.getLogger("httpcore").setLevel(logging.DEBUG)

    asc_api.configure_logging()

    assert logging.getLogger("httpx").level == logging.WARNING
    assert logging.getLogger("httpcore").level == logging.WARNING


@pytest.mark.parametrize(
    "script",
    [
        "upload_appstore_screenshots.py",
        "update_testflight_notes.py",
        "promote_testflight_external.py",
        "submit_appstore_release.py",
    ],
)
def test_each_asc_script_configures_logging_through_asc_api(script: str) -> None:
    # httpx logs each request URL at INFO. The upload URLs are pre-signed.
    source = (REPO_ROOT / "scripts" / script).read_text()
    main_block = source.split('if __name__ == "__main__":', 1)[1]

    assert "asc_api.configure_logging()" in main_block
    assert "basicConfig" not in source
