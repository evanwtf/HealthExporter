"""Promote an uploaded TestFlight build to external testers.

Resolves the build by its build number, adds it to the app's external beta
groups and creates a Beta App Review submission. External testers get the
build after Apple approves it. HealthExporter's external group is
"External Hoffgroup".

Examples:

    # Promote build 57 to every external group, then submit for beta review
    uv run scripts/promote_testflight_external.py --build 57

    # One group only, and no review submission
    uv run scripts/promote_testflight_external.py --build 57 \\
        --group "External Hoffgroup" --no-submit

    # Log the build state and the beta groups; change nothing
    uv run scripts/promote_testflight_external.py --build 57 --inspect

Environment: see scripts/asc_api.py.
"""

from __future__ import annotations

import argparse
import logging
import sys

import httpx

import asc_api
from asc_api import JSONObject

logger = logging.getLogger("promote_testflight_external")


def get_build(client: httpx.Client, app_id: str, build_number: str) -> JSONObject:
    data = asc_api.data_list(
        client.get(
            "/builds",
            params={
                "filter[app]": app_id,
                "filter[version]": build_number,
                "sort": "-uploadedDate",
                "fields[builds]": (
                    "version,processingState,expired,usesNonExemptEncryption"
                ),
                "limit": 1,
            },
        )
    )
    if not data:
        raise asc_api.ASCError(f"No build {build_number!r} found for app {app_id}")
    return data[0]


def get_beta_groups(client: httpx.Client, app_id: str) -> list[JSONObject]:
    return asc_api.data_list(
        client.get(
            "/betaGroups",
            params={
                "filter[app]": app_id,
                "fields[betaGroups]": "name,isInternalGroup,publicLinkEnabled",
                "limit": 50,
            },
        )
    )


def select_groups(groups: list[JSONObject], wanted: list[str]) -> list[JSONObject]:
    """The external groups to promote to: all of them, or the named ones.

    Names match without regard to case. An internal group never matches.
    """
    external = [g for g in groups if not g["attributes"]["isInternalGroup"]]
    targets = external
    if wanted:
        names = {name.casefold() for name in wanted}
        targets = [g for g in external if g["attributes"]["name"].casefold() in names]
        missing = names - {g["attributes"]["name"].casefold() for g in targets}
        if missing:
            raise asc_api.ASCError(f"No external group named: {sorted(missing)}")
    if not targets:
        raise asc_api.ASCError("No external beta group found to promote the build to")
    return targets


def check_promotable(build: JSONObject) -> None:
    attrs = build["attributes"]
    if attrs["processingState"] != "VALID":
        raise asc_api.ASCError(
            f"Build {attrs['version']} is {attrs['processingState']}, not VALID; "
            "wait for processing to finish before promoting"
        )
    if attrs["expired"]:
        raise asc_api.ASCError(f"Build {attrs['version']} is expired")


def add_build_to_group(client: httpx.Client, group_id: str, build_id: str) -> None:
    response = client.post(
        f"/betaGroups/{group_id}/relationships/builds",
        json={"data": [{"type": "builds", "id": build_id}]},
    )
    if response.status_code not in (200, 204):
        raise asc_api.ASCError(
            f"Could not add the build to group {group_id}: "
            f"{response.status_code} {response.text[:400]}"
        )


def submit_for_review(client: httpx.Client, build_id: str) -> str:
    """Return "submitted", or "already-submitted" when a submission exists."""
    response = client.post(
        "/betaAppReviewSubmissions",
        json={
            "data": {
                "type": "betaAppReviewSubmissions",
                "relationships": {
                    "build": {"data": {"type": "builds", "id": build_id}}
                },
            }
        },
    )
    if response.status_code in (200, 201):
        return "submitted"
    # 409 Conflict: a submission already exists for this build.
    if response.status_code == 409:
        return "already-submitted"
    raise asc_api.ASCError(
        "Could not submit the build for beta review: "
        f"{response.status_code} {response.text[:400]}"
    )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(__doc__ or "").split("\n", 1)[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(__doc__ or "").split("\n", 1)[1],
    )
    parser.add_argument("--build", required=True, help="Build number, e.g. 57.")
    parser.add_argument(
        "--group",
        action="append",
        default=[],
        help=(
            "External beta group to add the build to (repeatable). "
            "Default: every external group."
        ),
    )
    parser.add_argument(
        "--no-submit",
        action="store_true",
        help="Add the build to the groups, but do not submit it for beta review.",
    )
    parser.add_argument(
        "--inspect",
        action="store_true",
        help="Log the build state and the beta groups, then exit with no change.",
    )
    parser.add_argument(
        "--bundle-id",
        default=asc_api.bundle_id_from_env(),
        help=f"App bundle identifier (default: {asc_api.DEFAULT_BUNDLE_ID}).",
    )
    return parser.parse_args(argv)


def run(client: httpx.Client, args: argparse.Namespace) -> None:
    app_id = asc_api.get_app_id(client, args.bundle_id)
    build = get_build(client, app_id, args.build)
    attrs = build["attributes"]
    logger.info(
        "Build %s (id %s): state=%s expired=%s nonExemptEncryption=%s",
        attrs["version"],
        build["id"],
        attrs["processingState"],
        attrs["expired"],
        attrs.get("usesNonExemptEncryption"),
    )

    groups = get_beta_groups(client, app_id)
    for group in groups:
        group_attrs = group["attributes"]
        logger.info(
            "Group %r: internal=%s publicLink=%s id=%s",
            group_attrs["name"],
            group_attrs["isInternalGroup"],
            group_attrs.get("publicLinkEnabled"),
            group["id"],
        )

    if args.inspect:
        return

    check_promotable(build)
    targets = select_groups(groups, args.group)
    for group in targets:
        add_build_to_group(client, group["id"], build["id"])
        logger.info(
            "Added build %s to external group %r",
            attrs["version"],
            group["attributes"]["name"],
        )

    if args.no_submit:
        logger.info("Skipping the beta review submission (--no-submit)")
        return

    if submit_for_review(client, build["id"]) == "already-submitted":
        logger.info("Build %s already has a beta review submission", attrs["version"])
    else:
        logger.info("Submitted build %s for external beta review", attrs["version"])


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        with asc_api.client_from_env() as client:
            run(client, args)
    except (asc_api.ASCError, httpx.HTTPError) as exc:
        logger.error("%s", exc)
        return 1
    return 0


if __name__ == "__main__":
    asc_api.configure_logging()
    sys.exit(main())
