"""Check the version entries in the Xcode project, and a release tag.

Each target build configuration in project.pbxproj declares MARKETING_VERSION
and CURRENT_PROJECT_VERSION. The check fails when:

- a configuration declares one key but not the other,
- the MARKETING_VERSION entries differ, or the CURRENT_PROJECT_VERSION
  entries differ,
- a value is malformed (the version must be X.Y.Z, the build an integer),
- --tag is given and it is not "v" + MARKETING_VERSION.

Examples:

    uv run scripts/check_version.py
    uv run scripts/check_version.py --tag v2.5.4
    uv run scripts/check_version.py --github-output "$GITHUB_OUTPUT"
"""

from __future__ import annotations

import argparse
import logging
import re
import sys
from dataclasses import dataclass
from pathlib import Path

logger = logging.getLogger("check_version")

DEFAULT_PROJECT = Path("HealthExporter.xcodeproj/project.pbxproj")

MARKETING_KEY = "MARKETING_VERSION"
BUILD_KEY = "CURRENT_PROJECT_VERSION"

VERSION_PATTERN = re.compile(r"\d+\.\d+\.\d+")
BUILD_PATTERN = re.compile(r"\d+")

# One XCBuildConfiguration object: `<id> /* <name> */ = { isa = ...; ... };`
CONFIGURATION_PATTERN = re.compile(
    r"^\t\t\w+ /\* (?P<name>.*?) \*/ = \{\n"
    r"\t\t\tisa = XCBuildConfiguration;\n"
    r"(?P<body>.*?)"
    r"^\t\t\};$",
    re.MULTILINE | re.DOTALL,
)


def entry_pattern(key: str) -> re.Pattern[str]:
    """A `KEY = value;` build setting. The value is anything up to the `;`."""
    return re.compile(rf"^\s*{key} = (?P<value>[^;\n]*);$", re.MULTILINE)


class VersionError(Exception):
    """The project or the tag fails the check."""


@dataclass(frozen=True)
class ProjectVersion:
    marketing: str
    build: int

    @property
    def tag(self) -> str:
        return f"v{self.marketing}"


def configuration_entries(text: str) -> list[tuple[str, list[str], list[str]]]:
    """Return (name, marketing values, build values) for each configuration
    that declares at least one of the two keys."""
    found = []
    marketing_pattern = entry_pattern(MARKETING_KEY)
    build_pattern = entry_pattern(BUILD_KEY)
    for match in CONFIGURATION_PATTERN.finditer(text):
        body = match.group("body")
        marketing = [m.group("value") for m in marketing_pattern.finditer(body)]
        builds = [m.group("value") for m in build_pattern.finditer(body)]
        if marketing or builds:
            found.append((match.group("name"), marketing, builds))
    return found


def read_versions(text: str) -> ProjectVersion:
    """Return the one version and build the project declares, or raise."""
    entries = configuration_entries(text)
    if not entries:
        raise VersionError(f"The project has no {MARKETING_KEY} or {BUILD_KEY} entries")

    marketing_values: set[str] = set()
    build_values: set[str] = set()
    for name, marketing, builds in entries:
        if not marketing:
            raise VersionError(f"Configuration {name!r} has no {MARKETING_KEY}")
        if not builds:
            raise VersionError(f"Configuration {name!r} has no {BUILD_KEY}")
        marketing_values.update(marketing)
        build_values.update(builds)

    if len(marketing_values) != 1:
        raise VersionError(
            f"The {MARKETING_KEY} entries differ: {sorted(marketing_values)}"
        )
    if len(build_values) != 1:
        raise VersionError(f"The {BUILD_KEY} entries differ: {sorted(build_values)}")

    marketing_value = marketing_values.pop()
    build_value = build_values.pop()
    if not VERSION_PATTERN.fullmatch(marketing_value):
        raise VersionError(
            f"{MARKETING_KEY} is malformed: {marketing_value!r} is not X.Y.Z"
        )
    if not BUILD_PATTERN.fullmatch(build_value):
        raise VersionError(
            f"{BUILD_KEY} is malformed: {build_value!r} is not an integer"
        )
    return ProjectVersion(marketing=marketing_value, build=int(build_value))


def check_tag(tag: str, version: ProjectVersion) -> None:
    """Raise when the tag is not "v" + MARKETING_VERSION."""
    if tag != version.tag:
        raise VersionError(
            f"The tag {tag!r} does not match {MARKETING_KEY} "
            f"{version.marketing!r}: expected {version.tag!r}"
        )


def write_github_output(path: Path, version: ProjectVersion) -> None:
    with path.open("a") as handle:
        handle.write(f"version={version.marketing}\nbuild={version.build}\n")


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(__doc__ or "").split("\n", 1)[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(__doc__ or "").split("\n", 1)[1],
    )
    parser.add_argument(
        "--project",
        type=Path,
        default=DEFAULT_PROJECT,
        help=f"Path to project.pbxproj (default: {DEFAULT_PROJECT}).",
    )
    parser.add_argument("--tag", help='Release tag to check, e.g. "v2.5.4".')
    parser.add_argument(
        "--github-output",
        type=Path,
        help="Append version=X.Y.Z and build=N to this file (GITHUB_OUTPUT).",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        version = read_versions(args.project.read_text())
        if args.tag is not None:
            check_tag(args.tag, version)
    except (OSError, VersionError) as exc:
        logger.error("%s", exc)
        return 1

    logger.info(
        "%s: version %s, build %d", args.project, version.marketing, version.build
    )
    if args.tag is not None:
        logger.info("Tag %s matches the project", args.tag)
    if args.github_output is not None:
        write_github_output(args.github_output, version)
    return 0


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        stream=sys.stdout,
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
    )
    sys.exit(main())
