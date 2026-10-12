"""Update TestFlight "What to Test" notes via the App Store Connect API.

Resolves the build by its build number inside one marketing version (or picks
the most recent upload), then creates or updates the betaBuildLocalizations
resource for the locale.

Examples:

    # One exact build, notes from a file (what CI runs)
    uv run scripts/update_testflight_notes.py --build 57 --app-version 2.5.5 \\
        --notes-file ci/testflight-notes.txt

    # The most recent build, notes on the command line
    uv run scripts/update_testflight_notes.py --build latest --notes "Try export."

    # Show the build and its current notes; change nothing
    uv run scripts/update_testflight_notes.py --build 57 --app-version 2.5.5 --dry-run

Environment: see scripts/asc_api.py. Also ASC_LOCALE (default: en-US).
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path
from typing import Any

import httpx

import asc_api
from asc_api import JSONObject

logger = logging.getLogger("update_testflight_notes")

DEFAULT_LOCALE = "en-US"


def get_build(
    client: httpx.Client,
    app_id: str,
    build_version: str | None,
    app_version: str | None = None,
) -> JSONObject:
    """Return the build for the build number, or the latest upload.

    A build number is unique only within one marketing version. Pass
    `app_version` to restrict the lookup to that version: otherwise, before
    ASC lists a new upload, an older version's build with the same number
    can come back.
    """
    params: dict[str, Any] = {
        "filter[app]": app_id,
        "sort": "-uploadedDate",
        "limit": 1,
        "fields[builds]": "version,uploadedDate,processingState,expired",
    }
    if build_version is not None:
        params["filter[version]"] = build_version
    if app_version is not None:
        params["filter[preReleaseVersion.version]"] = app_version
        params["include"] = "preReleaseVersion"
        params["fields[builds]"] += ",preReleaseVersion"
        params["fields[preReleaseVersions]"] = "version"

    response = client.get("/builds", params=params)
    response.raise_for_status()
    body = response.json()
    data: list[JSONObject] = body.get("data", [])
    if not data:
        target = build_version if build_version is not None else "latest"
        if app_version is not None:
            target = f"{target} in {app_version}"
        raise asc_api.ASCError(f"No build found for {target!r}")
    build = data[0]
    if app_version is not None:
        train = build_train(build, body.get("included", []))
        if train != app_version:
            raise asc_api.ASCError(
                f"Build {build['id']} belongs to version {train!r}, not {app_version!r}"
            )
    return build


def build_train(build: JSONObject, included: list[JSONObject]) -> str | None:
    """The marketing version of the build, from the `included` resources."""
    ref = build.get("relationships", {}).get("preReleaseVersion", {}).get("data")
    if not ref:
        return None
    for entry in included:
        if entry.get("type") == ref.get("type") and entry.get("id") == ref.get("id"):
            version: str | None = entry.get("attributes", {}).get("version")
            return version
    return None


def get_localization(
    client: httpx.Client, build_id: str, locale: str
) -> JSONObject | None:
    entries = asc_api.data_list(
        client.get(
            f"/builds/{build_id}/betaBuildLocalizations",
            params={"fields[betaBuildLocalizations]": "locale,whatsNew"},
        )
    )
    for entry in entries:
        if entry.get("attributes", {}).get("locale") == locale:
            return entry
    return None


def create_localization(
    client: httpx.Client, build_id: str, locale: str, whats_new: str
) -> JSONObject:
    payload = {
        "data": {
            "type": "betaBuildLocalizations",
            "attributes": {"locale": locale, "whatsNew": whats_new},
            "relationships": {
                "build": {"data": {"type": "builds", "id": build_id}},
            },
        }
    }
    return asc_api.data_object(client.post("/betaBuildLocalizations", json=payload))


def update_localization(
    client: httpx.Client, localization_id: str, whats_new: str
) -> JSONObject:
    payload = {
        "data": {
            "type": "betaBuildLocalizations",
            "id": localization_id,
            "attributes": {"whatsNew": whats_new},
        }
    }
    return asc_api.data_object(
        client.patch(f"/betaBuildLocalizations/{localization_id}", json=payload)
    )


def read_notes(args: argparse.Namespace) -> str:
    if args.notes is not None and args.notes_file is not None:
        raise SystemExit("Pass either --notes or --notes-file, not both.")
    if args.notes is not None:
        return str(args.notes)
    if args.notes_file is not None:
        if args.notes_file == "-":
            return sys.stdin.read()
        return Path(args.notes_file).read_text()
    if not sys.stdin.isatty():
        return sys.stdin.read()
    raise SystemExit(
        "No notes provided. Use --notes TEXT, --notes-file PATH, or pipe on stdin."
    )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(__doc__ or "").split("\n", 1)[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(__doc__ or "").split("\n", 1)[1],
    )
    parser.add_argument(
        "--build",
        required=True,
        help='Build number (e.g. "57") or "latest" for the most recent upload.',
    )
    parser.add_argument(
        "--app-version",
        help=(
            'Marketing version of the build (e.g. "2.5.5"). Build numbers '
            "repeat across versions, so CI always passes this."
        ),
    )
    parser.add_argument("--notes", help='Inline "What to Test" text.')
    parser.add_argument(
        "--notes-file",
        help='Read notes from a file. Use "-" for stdin.',
    )
    parser.add_argument(
        "--bundle-id",
        default=asc_api.bundle_id_from_env(),
        help=f"App bundle identifier (default: {asc_api.DEFAULT_BUNDLE_ID}).",
    )
    parser.add_argument(
        "--locale",
        default=os.environ.get("ASC_LOCALE") or DEFAULT_LOCALE,
        help=f"Locale of the localization to update (default: {DEFAULT_LOCALE}).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Resolve and log the build and its current notes; change nothing.",
    )
    return parser.parse_args(argv)


def run(client: httpx.Client, args: argparse.Namespace, notes: str | None) -> None:
    app_id = asc_api.get_app_id(client, args.bundle_id)
    logger.info("Resolved app %s -> id=%s", args.bundle_id, app_id)

    build_version = None if args.build == "latest" else args.build
    build = get_build(client, app_id, build_version, args.app_version)
    build_id = build["id"]
    attrs = build["attributes"]
    logger.info(
        "Build %s (id=%s) uploaded %s state=%s",
        attrs.get("version"),
        build_id,
        attrs.get("uploadedDate"),
        attrs.get("processingState"),
    )

    existing = get_localization(client, build_id, args.locale)
    logger.info(
        "Existing %s localization: %s",
        args.locale,
        "<none>" if existing is None else f"id={existing['id']}",
    )
    if existing is not None and existing["attributes"].get("whatsNew"):
        logger.info("Current whatsNew: %r", existing["attributes"]["whatsNew"])

    if notes is None:
        logger.info("--dry-run: not modifying.")
        return

    if existing is None:
        result = create_localization(client, build_id, args.locale, notes)
        logger.info("Created localization id=%s", result["id"])
    else:
        result = update_localization(client, existing["id"], notes)
        logger.info("Updated localization id=%s", result["id"])


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    notes = None if args.dry_run else read_notes(args)
    try:
        with asc_api.client_from_env() as client:
            run(client, args, notes)
    except (asc_api.ASCError, httpx.HTTPError) as exc:
        logger.error("%s", exc)
        return 1
    return 0


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        stream=sys.stdout,
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
    )
    sys.exit(main())
