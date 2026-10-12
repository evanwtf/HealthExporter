"""Prepare an App Store version and submit it for App Review via the ASC API.

The script works in two phases.

Phase 1 reads only. It finds the build and the App Store version, and checks
the version's metadata: the description, the keywords, the support URL, What's
New, the 6.9-inch iPhone screenshots, the privacy policy URL and the App Review
contact. It also reads the open review submissions. It collects every problem
and refuses with the full list before any write.

Phase 2 writes, in mode prepare or submit. It creates the version or renames
the editable one, sets the release type, attaches the build, sets What's New
and sets the App Review contact. Mode submit then adds the version to a review
submission and submits it.

What's New: the script keeps the text in App Store Connect. When that text is
empty, or with --replace-whats-new, it uses the version's section of the
changelog.

The App Review contact comes from these environment variables. A set variable
wins over the value in App Store Connect. The script never logs the values.

    ASC_REVIEW_CONTACT_FIRST_NAME
    ASC_REVIEW_CONTACT_LAST_NAME
    ASC_REVIEW_CONTACT_EMAIL
    ASC_REVIEW_CONTACT_PHONE   "+", the country code, then the number

Examples:

    # Check everything and log the plan; write nothing (the default)
    uv run scripts/submit_appstore_release.py --version 2.5.5

    # Attach build 57 and set the metadata; do not submit
    uv run scripts/submit_appstore_release.py --version 2.5.5 --build 57 \\
        --mode prepare

    # Submit for App Review, and hold the release for a manual release
    uv run scripts/submit_appstore_release.py --version 2.5.5 --mode submit \\
        --release-type manual

Environment: see scripts/asc_api.py. Exit status 1 means a refusal or an App
Store Connect error.
"""

from __future__ import annotations

import argparse
import logging
import os
import re
import sys
from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import httpx

import asc_api
import changelog
from asc_api import JSONObject

logger = logging.getLogger("submit_appstore_release")

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CHANGELOG = REPO_ROOT / "docs" / "changelog.md"
DEFAULT_LOCALE = "en-US"

MODES = ("dry-run", "prepare", "submit")
RELEASE_TYPES = {"after-approval": "AFTER_APPROVAL", "manual": "MANUAL"}

SCREENSHOT_DISPLAY_TYPE = "APP_IPHONE_67"
# App Store Connect allows this many characters in What's New.
MAX_WHATS_NEW_LENGTH = changelog.MAX_NOTES_LENGTH

# Review submission states. App Review has the submission in these states.
IN_REVIEW_SUBMISSION_STATES = ("WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES")
DRAFT_SUBMISSION_STATE = "READY_FOR_REVIEW"

# A version that a failed run added to a draft submission is READY_FOR_REVIEW.
# It can still change, so the next run reuses it and the draft.
REUSABLE_VERSION_STATES = asc_api.EDITABLE_VERSION_STATES | {"READY_FOR_REVIEW"}

# appInfo states in which the app information can no longer change.
LOCKED_APP_INFO_STATES = frozenset({"READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_INFO"})


@dataclass(frozen=True)
class ContactField:
    attribute: str
    env: str
    label: str


CONTACT_FIELDS = (
    ContactField("contactFirstName", "ASC_REVIEW_CONTACT_FIRST_NAME", "first name"),
    ContactField("contactLastName", "ASC_REVIEW_CONTACT_LAST_NAME", "last name"),
    ContactField("contactEmail", "ASC_REVIEW_CONTACT_EMAIL", "email"),
    ContactField("contactPhone", "ASC_REVIEW_CONTACT_PHONE", "phone"),
)

VERSION_PATTERN = re.compile(r"\d+\.\d+\.\d+")
BUILD_PATTERN = re.compile(r"[1-9]\d*")
PHONE_PATTERN = re.compile(r"\+[0-9 ().\-]+")
MIN_PHONE_DIGITS = 8


class RefusedError(Exception):
    """A check failed. The message lists every problem."""

    def __init__(self, problems: list[str]) -> None:
        super().__init__("\n".join(problems))
        self.problems = problems


@dataclass
class Plan:
    """What phase 1 found, and what phase 2 will write."""

    version: str
    mode: str
    release_type: str
    app_id: str = ""
    build_id: str | None = None
    build_number: str | None = None
    # "reuse", "rename" or "create".
    version_action: str | None = None
    version_id: str | None = None
    version_state: str | None = None
    old_version_string: str | None = None
    localization_id: str | None = None
    whats_new: str | None = None
    whats_new_source: str | None = None
    whats_new_changes: bool = False
    changelog_text: str | None = None
    review_detail_id: str | None = None
    demo_account_required: bool | None = None
    contact: dict[str, str] = field(default_factory=dict)
    # Only the values from the secrets. A kept value is not sent again, so an
    # API error cannot repeat it.
    contact_updates: dict[str, str] = field(default_factory=dict)
    contact_status: dict[str, str] = field(default_factory=dict)
    # "reuse" or "create" in modes submit and dry-run; None in mode prepare.
    submission_action: str | None = None
    submission_id: str | None = None
    submission_has_version: bool = False
    problems: list[str] = field(default_factory=list)


# --- API helpers -----------------------------------------------------------


def api_error(response: httpx.Response, action: str) -> asc_api.ASCError:
    """An error with the API's error titles and details. They hold no secret."""
    try:
        errors: list[JSONObject] = response.json().get("errors", [])
    except ValueError:
        errors = []
    parts = [
        f"{e.get('title', 'error')}: {e.get('detail', '')}".rstrip(": ") for e in errors
    ]
    detail = "; ".join(parts) if parts else "no error details"
    return asc_api.ASCError(f"{action}: HTTP {response.status_code}. {detail}")


def ensure_ok(response: httpx.Response, action: str) -> httpx.Response:
    if response.status_code >= 400:
        raise api_error(response, action)
    return response


def get_list(
    client: httpx.Client, path: str, params: Mapping[str, Any], action: str
) -> httpx.Response:
    return ensure_ok(client.get(path, params=dict(params)), action)


def write(
    client: httpx.Client, method: str, path: str, body: JSONObject, action: str
) -> httpx.Response:
    response = ensure_ok(client.request(method, path, json=body), action)
    logger.info("%s: done", action)
    return response


def version_key(value: str) -> tuple[int, ...] | None:
    """The numeric parts of a version string, or None when it is not X.Y.Z."""
    if not VERSION_PATTERN.fullmatch(value):
        return None
    return tuple(int(part) for part in value.split("."))


# --- Phase 1: the read-only checks -----------------------------------------


def check_build(client: httpx.Client, plan: Plan, build_number: str | None) -> None:
    """Check 1: the build exists, is VALID, unexpired, answers the export
    compliance question, and belongs to the version."""
    params: dict[str, Any] = {
        "filter[app]": plan.app_id,
        "sort": "-uploadedDate",
        "include": "preReleaseVersion",
        "fields[builds]": (
            "version,uploadedDate,processingState,expired,"
            "usesNonExemptEncryption,preReleaseVersion"
        ),
        "fields[preReleaseVersions]": "version,platform",
        "limit": 50,
    }
    if build_number is None:
        params["filter[preReleaseVersion.version]"] = plan.version
    else:
        params["filter[version]"] = build_number
    response = get_list(client, "/builds", params, "List the builds")
    body = response.json()
    builds: list[JSONObject] = body.get("data", [])
    trains = {
        str(item["id"]): str(item.get("attributes", {}).get("version"))
        for item in body.get("included", [])
        if item.get("type") == "preReleaseVersions"
    }

    def train(build: JSONObject) -> str | None:
        related = build.get("relationships", {}).get("preReleaseVersion", {})
        data = related.get("data") or {}
        return trains.get(str(data.get("id")))

    if build_number is None:
        usable = [
            b
            for b in builds
            if train(b) == plan.version
            and b["attributes"].get("processingState") == "VALID"
            and not b["attributes"].get("expired")
        ]
        usable.sort(
            key=lambda b: str(b["attributes"].get("uploadedDate")), reverse=True
        )
        if not usable:
            found = ", ".join(
                f"{b['attributes'].get('version')} "
                f"({b['attributes'].get('processingState')}"
                f"{', expired' if b['attributes'].get('expired') else ''})"
                for b in builds
            )
            plan.problems.append(
                f"No VALID, unexpired build for version {plan.version}. "
                f"Builds found: {found or 'none'}."
            )
            return
        build = usable[0]
    else:
        if not builds:
            plan.problems.append(f"No build {build_number} in App Store Connect.")
            return
        matching = [b for b in builds if train(b) == plan.version]
        build = matching[0] if matching else builds[0]

    attrs = build["attributes"]
    plan.build_id = str(build["id"])
    plan.build_number = str(attrs.get("version"))
    logger.info(
        "Build %s (id %s): version %s, %s, expired=%s, usesNonExemptEncryption=%s",
        plan.build_number,
        plan.build_id,
        train(build),
        attrs.get("processingState"),
        attrs.get("expired"),
        attrs.get("usesNonExemptEncryption"),
    )
    name = f"Build {plan.build_number}"
    if train(build) != plan.version:
        plan.problems.append(
            f"{name} is version {train(build)}, not {plan.version}. "
            "Pass the build of this version, or leave --build out."
        )
    if attrs.get("processingState") != "VALID":
        plan.problems.append(
            f"{name} is {attrs.get('processingState')}, not VALID. "
            "Wait until App Store Connect finishes processing it."
        )
    if attrs.get("expired"):
        plan.problems.append(f"{name} is expired.")
    if attrs.get("usesNonExemptEncryption") is None:
        plan.problems.append(
            f"{name} has no export compliance answer. "
            "ITSAppUsesNonExemptEncryption must be in the Info.plist."
        )


def check_version(client: httpx.Client, plan: Plan) -> None:
    """Check 2: find the App Store version to use, or plan to make it."""
    versions = asc_api.data_list(
        get_list(
            client,
            f"/apps/{plan.app_id}/appStoreVersions",
            {
                "filter[platform]": "IOS",
                "fields[appStoreVersions]": (
                    "versionString,appVersionState,appStoreState,releaseType"
                ),
                "limit": 200,
            },
            "List the App Store versions",
        )
    )

    def version_string(v: JSONObject) -> str:
        return str(v.get("attributes", {}).get("versionString"))

    same = [v for v in versions if version_string(v) == plan.version]
    if same:
        found = same[0]
        state = asc_api.version_state(found)
        if state not in REUSABLE_VERSION_STATES:
            plan.problems.append(
                f"App Store version {plan.version} is {state}; it cannot change. "
                "A new release needs a new version number."
            )
            return
        plan.version_action = "reuse"
        plan.version_id = str(found["id"])
        plan.version_state = state
        return

    editable = [
        v for v in versions if asc_api.version_state(v) in REUSABLE_VERSION_STATES
    ]
    if not editable:
        plan.version_action = "create"
        return
    if len(editable) > 1:
        names = ", ".join(
            f"{version_string(v)} ({asc_api.version_state(v)})" for v in editable
        )
        plan.problems.append(f"More than one editable App Store version: {names}.")
        return
    other = editable[0]
    other_string = version_string(other)
    other_state = asc_api.version_state(other)
    other_key = version_key(other_string)
    wanted_key = version_key(plan.version)
    if (
        other_state == "PREPARE_FOR_SUBMISSION"
        and other_key is not None
        and wanted_key is not None
        and other_key < wanted_key
    ):
        plan.version_action = "rename"
        plan.version_id = str(other["id"])
        plan.version_state = other_state
        plan.old_version_string = other_string
        return
    plan.problems.append(
        f"App Store version {other_string} is editable ({other_state}), and App "
        f"Store Connect allows one editable version. The script renames only a "
        f"lower version in PREPARE_FOR_SUBMISSION to {plan.version}. Submit, "
        f"remove or rename {other_string} in App Store Connect first."
    )


def whats_new_problems(text: str) -> list[str]:
    """The reasons App Store Connect would refuse this What's New text."""
    problems: list[str] = []
    if not text.strip():
        problems.append("What's New is empty.")
    if len(text) > MAX_WHATS_NEW_LENGTH:
        problems.append(
            f"What's New is {len(text)} characters; App Store Connect allows "
            f"{MAX_WHATS_NEW_LENGTH}."
        )
    found = [c for c in changelog.MARKUP_CHARACTERS if c in text]
    if found:
        problems.append(
            f"What's New has {' and '.join(repr(c) for c in found)}. App Store "
            "Connect refuses them as markup."
        )
    return problems


def load_changelog_text(plan: Plan, path: Path) -> None:
    """Read the version's changelog section into plan.changelog_text."""
    try:
        text = changelog.notes(path.read_text(), plan.version).strip()
    except (OSError, changelog.ChangelogError) as error:
        plan.problems.append(f"What's New from the changelog: {error}")
        return
    problems = whats_new_problems(text)
    if problems:
        plan.problems.extend(f"What's New from the changelog: {p}" for p in problems)
        return
    plan.changelog_text = text


def check_localization(
    client: httpx.Client, plan: Plan, args: argparse.Namespace
) -> None:
    """Checks 3 and 4: the localization's metadata and What's New."""
    assert plan.version_id is not None
    localizations = asc_api.data_list(
        get_list(
            client,
            f"/appStoreVersions/{plan.version_id}/appStoreVersionLocalizations",
            {
                "fields[appStoreVersionLocalizations]": (
                    "locale,description,keywords,supportUrl,whatsNew"
                ),
                "limit": 50,
            },
            "List the version localizations",
        )
    )
    match = [
        loc
        for loc in localizations
        if loc.get("attributes", {}).get("locale") == args.locale
    ]
    if not match:
        found = sorted(
            str(loc.get("attributes", {}).get("locale")) for loc in localizations
        )
        plan.problems.append(f"The version has no {args.locale} localization: {found}.")
        return
    localization = match[0]
    plan.localization_id = str(localization["id"])
    attrs = localization.get("attributes", {})
    for name in ("description", "keywords", "supportUrl"):
        if not str(attrs.get(name) or "").strip():
            plan.problems.append(f"The {args.locale} {name} is empty.")

    current = str(attrs.get("whatsNew") or "")
    if current.strip() and not args.replace_whats_new:
        plan.whats_new = current
        plan.whats_new_source = "kept from App Store Connect"
        return
    if plan.changelog_text is None:
        load_changelog_text(plan, args.changelog)
    if plan.changelog_text is None:
        return
    plan.whats_new = plan.changelog_text
    plan.whats_new_source = "from the changelog"
    plan.whats_new_changes = plan.changelog_text != current


def check_screenshots(client: httpx.Client, plan: Plan) -> None:
    """Check 5: the 6.9-inch iPhone set has screenshots, all delivered."""
    assert plan.localization_id is not None
    sets = asc_api.data_list(
        get_list(
            client,
            f"/appStoreVersionLocalizations/{plan.localization_id}/appScreenshotSets",
            {"filter[screenshotDisplayType]": SCREENSHOT_DISPLAY_TYPE},
            "List the screenshot sets",
        )
    )
    if not sets:
        plan.problems.append(f"The {SCREENSHOT_DISPLAY_TYPE} screenshot set is empty.")
        return
    shots = asc_api.data_list(
        get_list(
            client,
            f"/appScreenshotSets/{sets[0]['id']}/appScreenshots",
            {"fields[appScreenshots]": "fileName,assetDeliveryState", "limit": 50},
            "List the screenshots",
        )
    )
    if not shots:
        plan.problems.append(f"The {SCREENSHOT_DISPLAY_TYPE} screenshot set is empty.")
        return
    for shot in shots:
        attrs = shot.get("attributes", {})
        state = (attrs.get("assetDeliveryState") or {}).get("state")
        if state != "COMPLETE":
            plan.problems.append(
                f"Screenshot {attrs.get('fileName')} is {state}, not COMPLETE."
            )
    logger.info("Screenshots: %d in %s", len(shots), SCREENSHOT_DISPLAY_TYPE)


def pick_app_info(app_infos: list[JSONObject]) -> JSONObject | None:
    """The appInfo that the next release uses.

    App Store Connect keeps one appInfo for the live app and makes a second,
    editable one for the next version. Prefer an appInfo in an editable state,
    then any appInfo that is not locked. Else use the live one: a new appInfo
    starts as a copy of it.
    """

    def state(info: JSONObject) -> str | None:
        attrs = info.get("attributes", {})
        value = attrs.get("state") or attrs.get("appStoreState")
        return None if value is None else str(value)

    states = [(info, state(info)) for info in app_infos]
    editable = [i for i, s in states if s in asc_api.EDITABLE_VERSION_STATES]
    unlocked = [i for i, s in states if s not in LOCKED_APP_INFO_STATES]
    for candidates in (editable, unlocked, app_infos):
        if candidates:
            return candidates[0]
    return None


def check_privacy_policy(
    client: httpx.Client, plan: Plan, args: argparse.Namespace
) -> None:
    """Check 6: the app information has a privacy policy URL for the locale."""
    app_infos = asc_api.data_list(
        get_list(
            client,
            f"/apps/{plan.app_id}/appInfos",
            {"fields[appInfos]": "state,appStoreState", "limit": 10},
            "List the app information",
        )
    )
    info = pick_app_info(app_infos)
    if info is None:
        plan.problems.append("The app has no app information in App Store Connect.")
        return
    localizations = asc_api.data_list(
        get_list(
            client,
            f"/appInfos/{info['id']}/appInfoLocalizations",
            {"fields[appInfoLocalizations]": "locale,privacyPolicyUrl", "limit": 50},
            "List the app information localizations",
        )
    )
    for loc in localizations:
        attrs = loc.get("attributes", {})
        if attrs.get("locale") == args.locale:
            url = str(attrs.get("privacyPolicyUrl") or "").strip()
            if url:
                logger.info("Privacy policy URL (%s): %s", args.locale, url)
                return
    plan.problems.append(f"The {args.locale} privacy policy URL is empty.")


def valid_email(value: str) -> bool:
    if value.count("@") != 1 or any(c.isspace() for c in value):
        return False
    local, domain = value.split("@")
    return bool(local) and "." in domain.strip(".") and not domain.startswith(".")


def valid_phone(value: str) -> bool:
    digits = sum(c.isdigit() for c in value)
    return bool(PHONE_PATTERN.fullmatch(value)) and digits >= MIN_PHONE_DIGITS


def check_review_contact(
    client: httpx.Client, plan: Plan, env: Mapping[str, str]
) -> None:
    """Check 7: each App Review contact field has a valid value.

    Never log or report a value: the CI log is public.
    """
    assert plan.version_id is not None
    response = client.get(
        f"/appStoreVersions/{plan.version_id}/appStoreReviewDetail",
        params={
            "fields[appStoreReviewDetails]": (
                "contactFirstName,contactLastName,contactEmail,contactPhone,"
                "demoAccountRequired"
            )
        },
    )
    detail: JSONObject | None = None
    if response.status_code != 404:
        detail = ensure_ok(response, "Read the App Review detail").json().get("data")
    existing: Mapping[str, Any] = {}
    if detail:
        plan.review_detail_id = str(detail["id"])
        existing = detail.get("attributes", {})
        demo = existing.get("demoAccountRequired")
        plan.demo_account_required = None if demo is None else bool(demo)

    for item in CONTACT_FIELDS:
        from_env = env.get(item.env, "").strip()
        kept = str(existing.get(item.attribute) or "").strip()
        if from_env:
            plan.contact[item.attribute] = from_env
            plan.contact_updates[item.attribute] = from_env
            plan.contact_status[item.label] = "set from secret"
        elif kept:
            plan.contact[item.attribute] = kept
            plan.contact_status[item.label] = "kept"
        else:
            plan.contact_status[item.label] = "missing"
            plan.problems.append(
                f"The App Review contact {item.label} is missing. "
                f"Set the secret {item.env}."
            )
    email = plan.contact.get("contactEmail")
    if email is not None and not valid_email(email):
        plan.problems.append(
            f"The App Review contact email ({plan.contact_status['email']}) is "
            "not an email address."
        )
    phone = plan.contact.get("contactPhone")
    if phone is not None and not valid_phone(phone):
        plan.problems.append(
            f"The App Review contact phone ({plan.contact_status['phone']}) is "
            "not valid. Write '+', the country code and the number, with at "
            f"least {MIN_PHONE_DIGITS} digits."
        )


def check_version_content(
    client: httpx.Client, plan: Plan, args: argparse.Namespace, env: Mapping[str, str]
) -> None:
    """Checks 3, 4, 5 and 7: they read the version itself."""
    check_localization(client, plan, args)
    if plan.localization_id is not None:
        check_screenshots(client, plan)
    check_review_contact(client, plan, env)


def check_submissions(client: httpx.Client, plan: Plan) -> None:
    """Check 8: no submission is in review; find a draft to reuse."""
    submissions = asc_api.data_list(
        get_list(
            client,
            "/reviewSubmissions",
            {
                "filter[app]": plan.app_id,
                "filter[platform]": "IOS",
                "filter[state]": ",".join(
                    [DRAFT_SUBMISSION_STATE, *IN_REVIEW_SUBMISSION_STATES]
                ),
                "fields[reviewSubmissions]": "platform,state",
                "limit": 50,
            },
            "List the review submissions",
        )
    )

    def state(s: JSONObject) -> str:
        return str(s.get("attributes", {}).get("state"))

    for submission in submissions:
        if state(submission) == "UNRESOLVED_ISSUES":
            plan.problems.append(
                f"Review submission {submission['id']} has unresolved issues: App "
                "Review rejected it. Answer App Review in App Store Connect, and "
                "resubmit there."
            )
        elif state(submission) in IN_REVIEW_SUBMISSION_STATES:
            plan.problems.append(
                f"Review submission {submission['id']} is already in review "
                f"({state(submission)}). Wait for App Review, or cancel it in "
                "App Store Connect."
            )
    drafts = [s for s in submissions if state(s) == DRAFT_SUBMISSION_STATE]
    # Mode prepare never submits. A dry run shows what mode submit would do.
    if plan.mode == "prepare":
        return
    if not drafts:
        plan.submission_action = "create"
        return
    plan.submission_action = "reuse"
    plan.submission_id = str(drafts[0]["id"])
    if plan.version_id is None:
        return
    items = get_list(
        client,
        f"/reviewSubmissions/{plan.submission_id}/items",
        {"include": "appStoreVersion", "limit": 50},
        "List the review submission items",
    ).json()
    for item in items.get("data", []):
        related = item.get("relationships", {}).get("appStoreVersion", {})
        data = related.get("data") or {}
        if data.get("id") == plan.version_id:
            plan.submission_has_version = True


def gather(
    client: httpx.Client, args: argparse.Namespace, env: Mapping[str, str]
) -> Plan:
    """Phase 1: run every read-only check and collect the problems."""
    plan = Plan(
        version=args.version,
        mode=args.mode,
        release_type=RELEASE_TYPES[args.release_type],
    )
    plan.app_id = asc_api.get_app_id(client, args.bundle_id)
    check_build(client, plan, args.build)
    check_version(client, plan)
    if plan.version_id is not None:
        check_version_content(client, plan, args, env)
    elif plan.version_action == "create":
        logger.info(
            "Version %s does not exist yet. The localization, What's New, "
            "screenshot and App Review contact checks run after the create.",
            plan.version,
        )
        # What's New of a new version is empty: check the changelog now.
        load_changelog_text(plan, args.changelog)
    check_privacy_policy(client, plan, args)
    check_submissions(client, plan)
    return plan


def log_plan(plan: Plan) -> None:
    logger.info("Plan for App Store version %s (mode %s):", plan.version, plan.mode)
    logger.info("  Build: %s (id %s)", plan.build_number, plan.build_id)
    if plan.version_action == "reuse":
        logger.info(
            "  Version: reuse %s (id %s, %s)",
            plan.version,
            plan.version_id,
            plan.version_state,
        )
    elif plan.version_action == "rename":
        logger.info(
            "  Version: rename %s (id %s) to %s",
            plan.old_version_string,
            plan.version_id,
            plan.version,
        )
    elif plan.version_action == "create":
        logger.info("  Version: create %s", plan.version)
    logger.info("  Release type: %s", plan.release_type)
    if plan.whats_new is not None:
        logger.info(
            "  What's New: %s (%d characters)%s",
            plan.whats_new_source,
            len(plan.whats_new),
            "" if plan.whats_new_changes else ", no change",
        )
        for line in plan.whats_new.splitlines():
            logger.info("    %s", line)
    elif plan.changelog_text is not None:
        logger.info(
            "  What's New: from the changelog when the new version has none "
            "(%d characters)",
            len(plan.changelog_text),
        )
    for label, status in plan.contact_status.items():
        logger.info("  App Review contact %s: %s", label, status)
    when = " in mode submit" if plan.mode == "dry-run" else ""
    if plan.submission_action == "reuse":
        logger.info(
            "  Review submission%s: reuse %s (%s)",
            when,
            plan.submission_id,
            "the version is in it"
            if plan.submission_has_version
            else "add the version",
        )
    elif plan.submission_action == "create":
        logger.info("  Review submission%s: create one, add the version", when)
    else:
        logger.info("  Review submission: none in mode %s", plan.mode)


# --- Phase 2: the writes -----------------------------------------------------


def version_patch(version_id: str, attributes: JSONObject) -> JSONObject:
    return {
        "data": {"type": "appStoreVersions", "id": version_id, "attributes": attributes}
    }


def apply(
    client: httpx.Client, plan: Plan, args: argparse.Namespace, env: Mapping[str, str]
) -> None:
    """Phase 2: write the plan. Raise RefusedError when a check after the create
    fails."""
    assert plan.build_id is not None
    if plan.version_action == "create":
        created = write(
            client,
            "POST",
            "/appStoreVersions",
            {
                "data": {
                    "type": "appStoreVersions",
                    "attributes": {
                        "platform": "IOS",
                        "versionString": plan.version,
                        "releaseType": plan.release_type,
                    },
                    "relationships": {
                        "app": {"data": {"type": "apps", "id": plan.app_id}}
                    },
                }
            },
            f"Create App Store version {plan.version}",
        )
        plan.version_id = str(created.json()["data"]["id"])
        check_version_content(client, plan, args, env)
        if plan.problems:
            raise RefusedError(
                [
                    f"Created version {plan.version} (id {plan.version_id}), but "
                    "it fails these checks. Nothing else was written:",
                    *plan.problems,
                ]
            )
        log_plan(plan)
    assert plan.version_id is not None
    if plan.version_action == "rename":
        write(
            client,
            "PATCH",
            f"/appStoreVersions/{plan.version_id}",
            version_patch(plan.version_id, {"versionString": plan.version}),
            f"Rename version {plan.old_version_string} to {plan.version}",
        )
    if plan.version_action != "create":
        write(
            client,
            "PATCH",
            f"/appStoreVersions/{plan.version_id}",
            version_patch(plan.version_id, {"releaseType": plan.release_type}),
            f"Set the release type to {plan.release_type}",
        )
    write(
        client,
        "PATCH",
        f"/appStoreVersions/{plan.version_id}/relationships/build",
        {"data": {"type": "builds", "id": plan.build_id}},
        f"Attach build {plan.build_number}",
    )
    if plan.whats_new_changes:
        assert plan.localization_id is not None
        write(
            client,
            "PATCH",
            f"/appStoreVersionLocalizations/{plan.localization_id}",
            {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "id": plan.localization_id,
                    "attributes": {"whatsNew": plan.whats_new},
                }
            },
            f"Set What's New ({args.locale})",
        )
    attributes: JSONObject = dict(plan.contact_updates)
    if plan.demo_account_required is None:
        attributes["demoAccountRequired"] = False
    if plan.review_detail_id is not None and not attributes:
        logger.info("App Review contact: no change")
    elif plan.review_detail_id is None:
        write(
            client,
            "POST",
            "/appStoreReviewDetails",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "attributes": attributes,
                    "relationships": {
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": plan.version_id}
                        }
                    },
                }
            },
            "Create the App Review detail",
        )
    else:
        write(
            client,
            "PATCH",
            f"/appStoreReviewDetails/{plan.review_detail_id}",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "id": plan.review_detail_id,
                    "attributes": attributes,
                }
            },
            "Set the App Review contact",
        )
    if plan.mode != "submit":
        logger.info("Mode prepare: version %s is ready. Not submitted.", plan.version)
        return

    if plan.submission_action == "create":
        created = write(
            client,
            "POST",
            "/reviewSubmissions",
            {
                "data": {
                    "type": "reviewSubmissions",
                    "attributes": {"platform": "IOS"},
                    "relationships": {
                        "app": {"data": {"type": "apps", "id": plan.app_id}}
                    },
                }
            },
            "Create a review submission",
        )
        plan.submission_id = str(created.json()["data"]["id"])
    assert plan.submission_id is not None
    if not plan.submission_has_version:
        write(
            client,
            "POST",
            "/reviewSubmissionItems",
            {
                "data": {
                    "type": "reviewSubmissionItems",
                    "relationships": {
                        "reviewSubmission": {
                            "data": {
                                "type": "reviewSubmissions",
                                "id": plan.submission_id,
                            }
                        },
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": plan.version_id}
                        },
                    },
                }
            },
            f"Add version {plan.version} to review submission {plan.submission_id}",
        )
    write(
        client,
        "PATCH",
        f"/reviewSubmissions/{plan.submission_id}",
        {
            "data": {
                "type": "reviewSubmissions",
                "id": plan.submission_id,
                "attributes": {"submitted": True},
            }
        },
        f"Submit review submission {plan.submission_id}",
    )
    logger.info(
        "Submitted version %s (build %s) for App Review; release type %s.",
        plan.version,
        plan.build_number,
        plan.release_type,
    )


def run(client: httpx.Client, args: argparse.Namespace, env: Mapping[str, str]) -> Plan:
    """Phase 1, then phase 2 unless the mode is dry-run. Raise RefusedError
    with every problem."""
    plan = gather(client, args, env)
    log_plan(plan)
    if plan.problems:
        raise RefusedError(plan.problems)
    if plan.mode == "dry-run":
        logger.info("Mode dry-run: every check passes. Nothing written.")
        return plan
    apply(client, plan, args, env)
    return plan


# --- Command line ------------------------------------------------------------


def redact(text: str, env: Mapping[str, str]) -> str:
    """Remove the App Review contact values from an error message."""
    for item in CONTACT_FIELDS:
        value = env.get(item.env, "").strip()
        if value:
            text = text.replace(value, "[redacted]")
    return text


def version_string(value: str) -> str:
    if not VERSION_PATTERN.fullmatch(value):
        raise argparse.ArgumentTypeError(f"{value!r} is not a version like 2.5.5")
    return value


def build_string(value: str) -> str:
    if not BUILD_PATTERN.fullmatch(value):
        raise argparse.ArgumentTypeError(f"{value!r} is not a build number like 57")
    return value


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    doc = __doc__ or ""
    parser = argparse.ArgumentParser(
        description=doc.split("\n", 1)[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=doc.split("\n", 1)[1],
    )
    parser.add_argument(
        "--version",
        required=True,
        type=version_string,
        help="App Store version, e.g. 2.5.5.",
    )
    parser.add_argument(
        "--build",
        type=build_string,
        help=(
            "Build number, e.g. 57. Default: the newest VALID, unexpired build "
            "of the version."
        ),
    )
    parser.add_argument(
        "--mode",
        choices=MODES,
        default="dry-run",
        help=(
            "dry-run: check and log the plan, write nothing. prepare: also "
            "write the version, the build and the metadata. submit: also "
            "submit for App Review. Default: %(default)s."
        ),
    )
    parser.add_argument(
        "--release-type",
        choices=sorted(RELEASE_TYPES),
        default="after-approval",
        help=(
            "Release when App Review approves, or hold for a manual release "
            "(default: %(default)s)."
        ),
    )
    parser.add_argument(
        "--locale",
        default=DEFAULT_LOCALE,
        help="Localization to check and change (default: %(default)s).",
    )
    parser.add_argument(
        "--changelog",
        type=Path,
        default=DEFAULT_CHANGELOG,
        help="Changelog with the What's New text (default: docs/changelog.md).",
    )
    parser.add_argument(
        "--replace-whats-new",
        action="store_true",
        help="Replace What's New with the changelog text, even when it is set.",
    )
    parser.add_argument(
        "--bundle-id",
        default=asc_api.bundle_id_from_env(),
        help=f"App bundle identifier (default: {asc_api.DEFAULT_BUNDLE_ID}).",
    )
    return parser.parse_args(argv)


def main(
    argv: list[str] | None = None,
    *,
    client_factory: Callable[[], httpx.Client] = asc_api.client_from_env,
    env: Mapping[str, str] | None = None,
) -> int:
    args = parse_args(argv)
    environment = os.environ if env is None else env
    try:
        with client_factory() as client:
            run(client, args, environment)
    except RefusedError as error:
        logger.error("Refused. %d problem(s):", len(error.problems))
        for problem in error.problems:
            logger.error("  %s", redact(problem, environment))
        return 1
    except (asc_api.ASCError, httpx.HTTPError) as error:
        logger.error("%s", redact(str(error), environment))
        return 1
    return 0


if __name__ == "__main__":
    asc_api.configure_logging()
    sys.exit(main())
