"""Replace the App Store iPhone screenshots of one version via the ASC API.

The manifest (ci/appstore-screenshots.txt) names the screenshots, in store
order. The source folder holds the PNGs that CI exports: the `screenshots`
artifact of an `iOS tests` or `TestFlight Upload` run.

The script checks every image before any write: each name has a file, each
size has an App Store slot, no image has an alpha channel, all images share
one display type, and the set has at most 10 images. It then checks that the
version exists, is editable, and has a localization for the locale.

After the checks, it deletes the screenshots in that display type's set,
uploads the manifest's images in order (reserve, upload, commit with the MD5),
waits until Apple marks each one delivered, and sets the order.

Examples:

    # Log the plan; write nothing
    uv run scripts/upload_appstore_screenshots.py --version 2.5.5 \\
        --source-dir screenshots --dry-run

    # Replace the iPhone screenshots of 2.5.5
    uv run scripts/upload_appstore_screenshots.py --version 2.5.5 \\
        --source-dir screenshots

Environment: see scripts/asc_api.py. Also ASC_LOCALE (default: en-US).
"""

from __future__ import annotations

import argparse
import hashlib
import logging
import os
import re
import struct
import sys
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import httpx

import asc_api
from asc_api import JSONObject

logger = logging.getLogger("upload_appstore_screenshots")

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_MANIFEST = REPO_ROOT / "ci" / "appstore-screenshots.txt"
DEFAULT_LOCALE = "en-US"

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
# PNG color types with an alpha channel: grayscale + alpha, and RGBA.
ALPHA_COLOR_TYPES = {4, 6}
MAX_SCREENSHOTS_PER_SET = 10
DELIVERY_TIMEOUT_SECONDS = 300.0
DELIVERY_POLL_SECONDS = 3.0

# Portrait pixel sizes and their App Store Connect display type. The 6.9-inch
# iPhone slot is the one App Store Connect requires; it scales the images down
# for the smaller iPhones.
DISPLAY_TYPES: dict[tuple[int, int], str] = {
    (1320, 2868): "APP_IPHONE_67",
    (1290, 2796): "APP_IPHONE_67",
}

# App Store version states in which the screenshots can change.
EDITABLE_STATES = asc_api.EDITABLE_VERSION_STATES

VERSION_PATTERN = re.compile(r"\d+\.\d+\.\d+")
NAME_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")


class ScreenshotError(Exception):
    """The screenshot set fails a check that comes before any write."""


@dataclass(frozen=True)
class PngHeader:
    width: int
    height: int
    has_alpha: bool


@dataclass(frozen=True)
class Screenshot:
    path: Path
    header: PngHeader


@dataclass(frozen=True)
class Plan:
    display_type: str
    screenshots: list[Screenshot]


def parse_manifest(text: str) -> list[str]:
    """The screenshot names, in order. `#` starts a comment."""
    names: list[str] = []
    for number, raw in enumerate(text.splitlines(), start=1):
        name = raw.split("#", 1)[0].strip()
        if not name:
            continue
        if name.endswith(".png") or not NAME_PATTERN.fullmatch(name) or ".." in name:
            raise ScreenshotError(
                f"manifest line {number}: {name!r} is not a screenshot name. "
                "Write the file name without .png and without a folder."
            )
        if name in names:
            raise ScreenshotError(f"manifest line {number}: {name} is listed twice")
        names.append(name)
    if not names:
        raise ScreenshotError("the manifest has no screenshot names")
    return names


def read_png_header(data: bytes) -> PngHeader:
    """The size and the alpha channel of a PNG, from the chunks before IDAT.

    A PNG has alpha when its color type carries alpha, or when a tRNS chunk
    makes a color transparent. Both make App Store Connect refuse the image.
    """
    if not data.startswith(PNG_SIGNATURE):
        raise ScreenshotError("not a PNG file")
    position = len(PNG_SIGNATURE)
    header: tuple[int, int, int] | None = None
    has_trns = False
    while position + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[position : position + 8])
        body = data[position + 8 : position + 8 + length]
        if len(body) != length:
            break
        if header is None:
            if kind != b"IHDR" or length != 13:
                break
            width, height, _depth, color_type = struct.unpack(">IIBB", body[:10])
            header = (width, height, color_type)
        elif kind == b"tRNS":
            has_trns = True
        elif kind == b"IDAT":
            break
        position += 12 + length
    if header is None:
        raise ScreenshotError("not a PNG file: no IHDR chunk")
    width, height, color_type = header
    return PngHeader(
        width=width,
        height=height,
        has_alpha=color_type in ALPHA_COLOR_TYPES or has_trns,
    )


def display_type(width: int, height: int) -> str:
    kind = DISPLAY_TYPES.get((width, height))
    if kind is None:
        accepted = ", ".join(f"{w} x {h}" for w, h in DISPLAY_TYPES)
        raise ScreenshotError(
            f"{width} x {height} has no App Store slot; expected one of {accepted}"
        )
    return kind


def build_plan(source_dir: Path, names: list[str]) -> Plan:
    """Check the manifest's images and return them in manifest order.

    Every problem is collected, so one run reports all of them.
    """
    problems: list[str] = []
    screenshots: list[Screenshot] = []
    kinds: dict[str, list[str]] = {}
    for name in names:
        path = source_dir / f"{name}.png"
        if not path.is_file():
            problems.append(f"{path.name}: no file in {source_dir}")
            continue
        try:
            header = read_png_header(path.read_bytes())
        except ScreenshotError as error:
            problems.append(f"{path.name}: {error}")
            continue
        found: list[str] = []
        try:
            kind = display_type(header.width, header.height)
        except ScreenshotError as error:
            found.append(str(error))
        if header.has_alpha:
            found.append("alpha channel; App Store Connect takes opaque images")
        if found:
            problems.extend(f"{path.name}: {problem}" for problem in found)
            continue
        kinds.setdefault(kind, []).append(path.name)
        screenshots.append(Screenshot(path=path, header=header))
    if len(kinds) > 1:
        detail = "; ".join(f"{k}: {', '.join(v)}" for k, v in sorted(kinds.items()))
        problems.append(f"the images span more than one display type ({detail})")
    if len(names) > MAX_SCREENSHOTS_PER_SET:
        problems.append(
            f"{len(names)} screenshots; the limit is {MAX_SCREENSHOTS_PER_SET}"
        )
    if problems:
        raise ScreenshotError(
            "refusing the screenshot set:\n" + "\n".join(f"  {p}" for p in problems)
        )
    (kind,) = kinds
    return Plan(display_type=kind, screenshots=screenshots)


def slices(data: bytes, operations: list[JSONObject]) -> list[bytes]:
    """Cut the file into the parts Apple asked for. They must cover it exactly."""
    ordered = sorted(operations, key=lambda op: int(op["offset"]))
    position = 0
    for op in ordered:
        if op["offset"] != position:
            break
        position += int(op["length"])
    if not ordered or position != len(data):
        spans = [(op["offset"], op["length"]) for op in ordered]
        raise asc_api.ASCError(
            f"the upload operations do not cover the file: {len(data)} bytes, "
            f"operations {spans}"
        )
    return [data[op["offset"] : op["offset"] + op["length"]] for op in operations]


def find_version(client: httpx.Client, app_id: str, version: str) -> JSONObject:
    """The iOS App Store version, refused when it is missing or locked."""
    versions = asc_api.data_list(
        client.get(
            f"/apps/{app_id}/appStoreVersions",
            params={
                "filter[versionString]": version,
                "filter[platform]": "IOS",
                "fields[appStoreVersions]": (
                    "versionString,appVersionState,appStoreState"
                ),
                "limit": 5,
            },
        )
    )
    if not versions:
        raise asc_api.ASCError(
            f"No App Store version {version}. Create it in App Store Connect first."
        )
    found = versions[0]
    state = asc_api.version_state(found)
    if state not in EDITABLE_STATES:
        raise asc_api.ASCError(
            f"Version {version} is {state}; its screenshots are locked. "
            f"Editable states: {', '.join(sorted(EDITABLE_STATES))}"
        )
    return found


def find_localization(client: httpx.Client, version_id: str, locale: str) -> str:
    entries = asc_api.data_list(
        client.get(
            f"/appStoreVersions/{version_id}/appStoreVersionLocalizations",
            params={"fields[appStoreVersionLocalizations]": "locale", "limit": 50},
        )
    )
    for entry in entries:
        if entry.get("attributes", {}).get("locale") == locale:
            return str(entry["id"])
    found = sorted(str(e.get("attributes", {}).get("locale")) for e in entries)
    raise asc_api.ASCError(f"No {locale!r} localization on the version; it has {found}")


def find_set(client: httpx.Client, localization_id: str, kind: str) -> str | None:
    data = asc_api.data_list(
        client.get(
            f"/appStoreVersionLocalizations/{localization_id}/appScreenshotSets",
            params={"filter[screenshotDisplayType]": kind},
        )
    )
    return str(data[0]["id"]) if data else None


def existing_screenshots(client: httpx.Client, set_id: str) -> list[JSONObject]:
    return asc_api.data_list(
        client.get(
            f"/appScreenshotSets/{set_id}/appScreenshots",
            params={"fields[appScreenshots]": "fileName", "limit": 50},
        )
    )


def create_set(client: httpx.Client, localization_id: str, kind: str) -> str:
    payload = {
        "data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": kind},
            "relationships": {
                "appStoreVersionLocalization": {
                    "data": {
                        "type": "appStoreVersionLocalizations",
                        "id": localization_id,
                    }
                }
            },
        }
    }
    return str(
        asc_api.data_object(client.post("/appScreenshotSets", json=payload))["id"]
    )


def upload_one(
    client: httpx.Client, uploader: httpx.Client, set_id: str, path: Path
) -> str:
    """Reserve, upload and commit one screenshot. Return its id.

    The upload URLs are pre-signed, so `uploader` must not carry the API token.
    """
    data = path.read_bytes()
    reserve = {
        "data": {
            "type": "appScreenshots",
            "attributes": {"fileName": path.name, "fileSize": len(data)},
            "relationships": {
                "appScreenshotSet": {
                    "data": {"type": "appScreenshotSets", "id": set_id}
                }
            },
        }
    }
    shot = asc_api.data_object(client.post("/appScreenshots", json=reserve))
    shot_id = str(shot["id"])
    operations: list[JSONObject] = shot["attributes"]["uploadOperations"]
    for op in operations:
        if op["method"] != "PUT":
            raise asc_api.ASCError(
                f"unexpected upload method {op['method']} for {path.name}"
            )
    for op, part in zip(operations, slices(data, operations), strict=True):
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        uploader.put(op["url"], content=part, headers=headers).raise_for_status()
    commit = {
        "data": {
            "type": "appScreenshots",
            "id": shot_id,
            "attributes": {
                "uploaded": True,
                "sourceFileChecksum": hashlib.md5(data).hexdigest(),
            },
        }
    }
    asc_api.data_object(client.patch(f"/appScreenshots/{shot_id}", json=commit))
    return shot_id


def wait_until_delivered(
    client: httpx.Client,
    shot_id: str,
    name: str,
    *,
    sleep: Callable[[float], None] = time.sleep,
    clock: Callable[[], float] = time.monotonic,
    timeout: float = DELIVERY_TIMEOUT_SECONDS,
) -> None:
    deadline = clock() + timeout
    while True:
        shot = asc_api.data_object(
            client.get(
                f"/appScreenshots/{shot_id}",
                params={"fields[appScreenshots]": "assetDeliveryState"},
            )
        )
        state: dict[str, Any] = shot["attributes"].get("assetDeliveryState") or {}
        if state.get("state") == "COMPLETE":
            return
        if state.get("state") == "FAILED":
            raise asc_api.ASCError(f"Apple rejected {name}: {state.get('errors')}")
        if clock() > deadline:
            raise asc_api.ASCError(
                f"{name} is still {state.get('state')} after {timeout:.0f} s"
            )
        sleep(DELIVERY_POLL_SECONDS)


def set_order(client: httpx.Client, set_id: str, shot_ids: list[str]) -> None:
    response = client.patch(
        f"/appScreenshotSets/{set_id}/relationships/appScreenshots",
        json={"data": [{"type": "appScreenshots", "id": i} for i in shot_ids]},
    )
    response.raise_for_status()


def run(
    client: httpx.Client,
    uploader: httpx.Client,
    args: argparse.Namespace,
    plan: Plan,
    *,
    sleep: Callable[[float], None] = time.sleep,
) -> None:
    app_id = asc_api.get_app_id(client, args.bundle_id)
    version = find_version(client, app_id, args.version)
    logger.info(
        "Version %s (id %s): %s",
        args.version,
        version["id"],
        asc_api.version_state(version),
    )
    localization_id = find_localization(client, version["id"], args.locale)
    set_id = find_set(client, localization_id, plan.display_type)
    old = existing_screenshots(client, set_id) if set_id else []
    logger.info(
        "%s %s: replace %d screenshot(s) (%s) with %d, in this order:",
        args.locale,
        plan.display_type,
        len(old),
        ", ".join(str(s.get("attributes", {}).get("fileName")) for s in old) or "none",
        len(plan.screenshots),
    )
    for position, shot in enumerate(plan.screenshots, start=1):
        logger.info(
            "  %d. %s (%d x %d)",
            position,
            shot.path.name,
            shot.header.width,
            shot.header.height,
        )
    if args.dry_run:
        logger.info("--dry-run: nothing written.")
        return

    if set_id is None:
        set_id = create_set(client, localization_id, plan.display_type)
        logger.info("Created the %s set (id %s)", plan.display_type, set_id)
    for old_shot in old:
        client.delete(f"/appScreenshots/{old_shot['id']}").raise_for_status()
        logger.info("Deleted %s", old_shot.get("attributes", {}).get("fileName"))
    new_ids: list[str] = []
    for shot in plan.screenshots:
        shot_id = upload_one(client, uploader, set_id, shot.path)
        wait_until_delivered(client, shot_id, shot.path.name, sleep=sleep)
        logger.info("Uploaded %s (id %s)", shot.path.name, shot_id)
        new_ids.append(shot_id)
    set_order(client, set_id, new_ids)
    logger.info("Set the order of %d screenshot(s). Done.", len(new_ids))


def version_string(value: str) -> str:
    if not VERSION_PATTERN.fullmatch(value):
        raise argparse.ArgumentTypeError(f"{value!r} is not a version like 2.5.5")
    return value


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(__doc__ or "").split("\n", 1)[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(__doc__ or "").split("\n", 1)[1],
    )
    parser.add_argument(
        "--version",
        required=True,
        type=version_string,
        help="App Store version, e.g. 2.5.5.",
    )
    parser.add_argument(
        "--source-dir",
        required=True,
        type=Path,
        help="Folder with the exported PNGs (the `screenshots` CI artifact).",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST,
        help="The screenshot names in store order (default: %(default)s).",
    )
    parser.add_argument(
        "--locale",
        default=os.environ.get("ASC_LOCALE") or DEFAULT_LOCALE,
        help=f"Localization to change (default: {DEFAULT_LOCALE}).",
    )
    parser.add_argument(
        "--bundle-id",
        default=asc_api.bundle_id_from_env(),
        help=f"App bundle identifier (default: {asc_api.DEFAULT_BUNDLE_ID}).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Check everything and log the plan; write nothing.",
    )
    return parser.parse_args(argv)


def default_uploader() -> httpx.Client:
    """A client for the pre-signed upload URLs: no API token."""
    return httpx.Client(timeout=120.0)


def main(
    argv: list[str] | None = None,
    *,
    client_factory: Callable[[], httpx.Client] = asc_api.client_from_env,
    uploader_factory: Callable[[], httpx.Client] = default_uploader,
) -> int:
    args = parse_args(argv)
    # Every local check runs before the first network call.
    try:
        names = parse_manifest(args.manifest.read_text())
        plan = build_plan(args.source_dir, names)
    except (OSError, ScreenshotError) as error:
        logger.error("%s", error)
        return 1
    logger.info(
        "Manifest %s: %d screenshot(s) from %s",
        args.manifest,
        len(plan.screenshots),
        args.source_dir,
    )
    try:
        with client_factory() as client, uploader_factory() as uploader:
            run(client, uploader, args, plan)
    except (asc_api.ASCError, httpx.HTTPError) as error:
        logger.error("%s", error)
        return 1
    return 0


if __name__ == "__main__":
    asc_api.configure_logging()
    sys.exit(main())
