"""Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in the Xcode project.

The script replaces every entry of each key, so no configuration keeps an old
value. It refuses a project that fails scripts/check_version.py, and it leaves
the file unchanged when it refuses.

The new version starts from the larger of MARKETING_VERSION and --latest-tag,
so a tag pushed by hand is never reused. The build number goes up by one.

Examples:

    uv run scripts/bump_version.py --part patch
    uv run scripts/bump_version.py --part minor --latest-tag v2.5.4 \\
        --github-output "$GITHUB_OUTPUT"
"""

from __future__ import annotations

import argparse
import logging
import re
import sys
from pathlib import Path

from check_version import (
    BUILD_KEY,
    DEFAULT_PROJECT,
    MARKETING_KEY,
    VERSION_PATTERN,
    ProjectVersion,
    VersionError,
    read_versions,
    write_github_output,
)

logger = logging.getLogger("bump_version")

PARTS = ("patch", "minor", "major")


def parse_version(value: str) -> tuple[int, int, int]:
    major, minor, patch = (int(part) for part in value.split("."))
    return major, minor, patch


def next_version(current: str, part: str, latest_tag: str | None = None) -> str:
    """Return the version after max(current, latest_tag), bumped at `part`."""
    if part not in PARTS:
        raise ValueError(f"Unknown part {part!r}: use one of {', '.join(PARTS)}")
    base = parse_version(current)
    if latest_tag:
        tagged = latest_tag.removeprefix("v")
        if not latest_tag.startswith("v") or not VERSION_PATTERN.fullmatch(tagged):
            raise VersionError(f"The latest tag {latest_tag!r} is not vX.Y.Z")
        base = max(base, parse_version(tagged))

    major, minor, patch = base
    if part == "major":
        return f"{major + 1}.0.0"
    if part == "minor":
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"


def bump(
    text: str, part: str, latest_tag: str | None = None
) -> tuple[str, ProjectVersion]:
    """Return the new project text and its version. Raise on a bad project."""
    current = read_versions(text)
    new = ProjectVersion(
        marketing=next_version(current.marketing, part, latest_tag),
        build=current.build + 1,
    )
    text = re.sub(
        rf"\b{MARKETING_KEY} = [^;\n]*;",
        f"{MARKETING_KEY} = {new.marketing};",
        text,
    )
    text = re.sub(
        rf"\b{BUILD_KEY} = [^;\n]*;",
        f"{BUILD_KEY} = {new.build};",
        text,
    )
    # The result must pass the same check the release runs before the tag.
    if read_versions(text) != new:
        raise VersionError(f"The bump did not produce {new}")
    return text, new


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(__doc__ or "").split("\n", 1)[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(__doc__ or "").split("\n", 1)[1],
    )
    parser.add_argument(
        "--part",
        required=True,
        choices=PARTS,
        help="The version part to bump.",
    )
    parser.add_argument(
        "--latest-tag",
        help='The newest vX.Y.Z tag, e.g. "v2.5.4". Empty or absent: none.',
    )
    parser.add_argument(
        "--project",
        type=Path,
        default=DEFAULT_PROJECT,
        help=f"Path to project.pbxproj (default: {DEFAULT_PROJECT}).",
    )
    parser.add_argument(
        "--github-output",
        type=Path,
        help="Append version=X.Y.Z and build=N to this file (GITHUB_OUTPUT).",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        before = args.project.read_text()
        old = read_versions(before)
        after, new = bump(before, args.part, args.latest_tag)
    except (OSError, VersionError) as exc:
        logger.error("%s", exc)
        return 1

    args.project.write_text(after)
    logger.info(
        "Bumped %s: version %s -> %s, build %d -> %d",
        args.part,
        old.marketing,
        new.marketing,
        old.build,
        new.build,
    )
    if args.github_output is not None:
        write_github_output(args.github_output, new)
    return 0


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        stream=sys.stdout,
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
    )
    sys.exit(main())
