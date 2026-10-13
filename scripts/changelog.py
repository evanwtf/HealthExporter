"""Check docs/changelog.md, cut a release in it, and write release notes.

docs/changelog.md is the one source of release notes. Its layout:

    # Changelog

    One short paragraph.

    ## Unreleased

    ## vX.Y.Z (build N), YYYY-MM-DD
    - A plain sentence for testers.

    ---

    A footer line.

`## Unreleased` is the first `##` section, and it appears once. Each other `##`
heading names one version, newest first. A `---` line after the sections
starts the footer, which is not part of any section. HTML comments
(`<!-- ... -->`) are removed before the notes are used or measured.

The notes are plain text: no backticks, bold, Markdown links, '<' or '>'.
App Store Connect refuses '<' and '>' in What's New. Each section is at most
4000 characters, the TestFlight limit.

A line that starts with "- Please" asks testers to check something. The
TestFlight notes keep it. The App Store What's New (`store_notes`) leaves it
out.

Subcommands:

    check [--require-unreleased]
        Fail when the file breaks the layout or a section breaks the rules.
        With --require-unreleased, also fail when ## Unreleased is empty.
    release --version X.Y.Z --build N --date YYYY-MM-DD
        Rename ## Unreleased to the version and add a new, empty
        ## Unreleased above it. On a refusal the file is unchanged.
    notes --version X.Y.Z --output FILE
        Write the section of the version, with the comments removed.

Examples:

    uv run scripts/changelog.py check --require-unreleased
    uv run scripts/changelog.py release --version 2.5.5 --build 57 \\
        --date "$(date -u +%F)"
    uv run scripts/changelog.py notes --version 2.5.5 --output notes.md
"""

from __future__ import annotations

import argparse
import datetime
import logging
import re
import sys
from dataclasses import dataclass
from pathlib import Path

logger = logging.getLogger("changelog")

DEFAULT_CHANGELOG = Path("docs/changelog.md")

TITLE = "# Changelog"
UNRELEASED = "Unreleased"
UNRELEASED_HINT = '<!-- One "- " line per change, in plain words for testers. -->'

# TestFlight rejects "What to Test" notes longer than this.
MAX_NOTES_LENGTH = 4000

VERSION_PATTERN = re.compile(r"\d+\.\d+\.\d+")
DATE_PATTERN = re.compile(r"\d{4}-\d{2}-\d{2}")
VERSION_HEADING = re.compile(
    r"## v(?P<version>\d+\.\d+\.\d+) \(build (?P<build>[1-9]\d*)\), "
    r"(?P<date>\d{4}-\d{2}-\d{2})"
)
HEADING_FORMAT = "## vX.Y.Z (build N), YYYY-MM-DD"

COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)
# A comment on lines of its own: remove the lines too, so no blank is left.
COMMENT_LINES = re.compile(
    r"^[ \t]*<!--(?:(?!-->).)*-->[ \t]*(?:\n|\Z)", re.DOTALL | re.MULTILINE
)
HEADING_LINE = re.compile(r"^##(?!#).*$", re.MULTILINE)
FOOTER_LINE = re.compile(r"^---[ \t]*$", re.MULTILINE)

# Markdown that a tester would see as raw characters in TestFlight.
FORMATTING = {"`": "a backtick", "**": "bold", "](": "a Markdown link"}
# App Store Connect refuses What's New text with these characters: "must not
# contain markup language".
MARKUP_CHARACTERS = ("<", ">")
# A line for testers only, for example "- Please check the permission sheet."
TESTER_REQUEST = re.compile(r"^- Please\b")


class ChangelogError(Exception):
    """The changelog or the request fails a rule."""


@dataclass(frozen=True)
class Section:
    title: str
    body: str
    start: int
    end: int
    version: str | None = None

    @property
    def name(self) -> str:
        return f"v{self.version}" if self.version else f"## {self.title}"


def version_key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def strip_comments(text: str) -> str:
    return COMMENT.sub("", COMMENT_LINES.sub("", text))


def tidy(text: str) -> str:
    """Remove trailing spaces and extra blank lines. End with one newline."""
    lines = "\n".join(line.rstrip() for line in text.split("\n"))
    lines = re.sub(r"\n{3,}", "\n\n", lines).strip("\n")
    return lines + "\n" if lines else ""


def notes_text(body: str) -> str:
    """The text testers see: the body with no comments and no extra blanks."""
    return tidy(strip_comments(body))


def mask_comments(text: str) -> str:
    """Blank out each comment but keep every offset and newline."""
    return COMMENT.sub(lambda m: re.sub(r"[^\n]", " ", m.group()), text)


def parse(text: str) -> list[Section]:
    """Return the sections in file order. Raise when the layout is wrong."""
    if text.split("\n", 1)[0] != TITLE:
        raise ChangelogError(f"The file must start with {TITLE!r}")
    if "<!--" in strip_comments(text):
        raise ChangelogError("A comment has no closing '-->'")

    masked = mask_comments(text)
    headings = list(HEADING_LINE.finditer(masked))
    end_of_sections = len(text)
    if headings:
        footer = FOOTER_LINE.search(masked, headings[0].start())
        if footer is not None:
            end_of_sections = footer.start()
            late = [h for h in headings if h.start() > end_of_sections]
            if late:
                raise ChangelogError(
                    f"The heading {late[0].group()!r} is after the footer ('---')"
                )

    sections = []
    for index, match in enumerate(headings):
        end = (
            headings[index + 1].start()
            if index + 1 < len(headings)
            else end_of_sections
        )
        heading = text[match.start() : match.end()]
        body = text[match.end() + 1 : end] if match.end() < end else ""
        title = heading.removeprefix("##").strip()
        version = None
        if title != UNRELEASED:
            version_match = VERSION_HEADING.fullmatch(heading)
            if version_match is None or not valid_date(version_match["date"]):
                raise ChangelogError(
                    f"Malformed heading {heading!r}: use {HEADING_FORMAT!r}"
                )
            version = version_match["version"]
        sections.append(
            Section(
                title=title,
                body=body,
                start=match.start(),
                end=end,
                version=version,
            )
        )

    check_order(sections)
    return sections


def check_order(sections: list[Section]) -> None:
    unreleased = [s for s in sections if s.version is None]
    if not unreleased:
        raise ChangelogError(f"The file has no '## {UNRELEASED}' section")
    if len(unreleased) > 1:
        raise ChangelogError(
            f"'## {UNRELEASED}' must appear exactly once; "
            f"it appears {len(unreleased)} times"
        )
    if sections[0].version is not None:
        raise ChangelogError(f"'## {UNRELEASED}' must be the first '##' section")

    seen: set[str] = set()
    previous: str | None = None
    for section in sections[1:]:
        assert section.version is not None
        if section.version in seen:
            raise ChangelogError(f"v{section.version} appears twice")
        seen.add(section.version)
        if previous is not None and version_key(section.version) > version_key(
            previous
        ):
            raise ChangelogError(
                f"The versions are out of order: v{section.version} is below "
                f"v{previous}. Put the newest first."
            )
        previous = section.version


def valid_date(value: str) -> bool:
    if not DATE_PATTERN.fullmatch(value):
        return False
    try:
        datetime.date.fromisoformat(value)
    except ValueError:
        return False
    return True


def check_section(section: Section) -> None:
    """Raise when the notes of one section are too long or not plain text."""
    notes = notes_text(section.body)
    if len(notes) > MAX_NOTES_LENGTH:
        raise ChangelogError(
            f"{section.name} is {len(notes)} characters; "
            f"TestFlight allows {MAX_NOTES_LENGTH}"
        )
    for marker, name in FORMATTING.items():
        if marker in notes:
            raise ChangelogError(
                f"{section.name} must be plain text for testers: it has {name} "
                f"({marker!r}). Move notes for developers into a comment."
            )
    found = [c for c in MARKUP_CHARACTERS if c in notes]
    if found:
        raise ChangelogError(
            f"{section.name} has {' and '.join(repr(c) for c in found)}. "
            "App Store Connect refuses them in What's New as markup. "
            "Write the words, such as 'more than' or 'less than'."
        )


def check(text: str, *, require_unreleased: bool = False) -> list[Section]:
    """Raise when the file or a section breaks a rule. Return the sections."""
    sections = parse(text)
    for section in sections:
        check_section(section)
    if require_unreleased and not notes_text(sections[0].body):
        raise ChangelogError(
            f"'## {UNRELEASED}' is empty. A release pull request adds one "
            f'"- " line per change under it; label the pull request '
            "skip-release when it cuts no release."
        )
    return sections


def release(text: str, version: str, build: int, date: str) -> str:
    """Return the text with ## Unreleased renamed to the version and a new,
    empty ## Unreleased above it. Raise and change nothing on a refusal."""
    if not VERSION_PATTERN.fullmatch(version):
        raise ChangelogError(f"The version {version!r} is not X.Y.Z")
    if build < 1:
        raise ChangelogError(f"The build {build} is not a positive integer")
    if not valid_date(date):
        raise ChangelogError(f"The date {date!r} is not YYYY-MM-DD")

    sections = check(text)
    unreleased = sections[0]
    if not notes_text(unreleased.body):
        raise ChangelogError(
            f"'## {UNRELEASED}' is empty: nothing to release as v{version}"
        )
    if any(s.version == version for s in sections):
        raise ChangelogError(f"v{version} already has a section")

    body = tidy(unreleased.body.replace(UNRELEASED_HINT, ""))
    rest = text[unreleased.end :]
    result = (
        text[: unreleased.start]
        + f"## {UNRELEASED}\n\n{UNRELEASED_HINT}\n\n"
        + f"## v{version} (build {build}), {date}\n\n"
        + body
        + ("\n" + rest if rest else "")
    )
    check(result)
    return result


def store_notes(notes_body: str) -> str:
    """The App Store What's New: the notes without the requests to testers.

    A line that starts with "- Please" asks testers to check something. App
    Store users cannot act on it, so What's New leaves it out.
    """
    kept = [line for line in notes_body.split("\n") if not TESTER_REQUEST.match(line)]
    return tidy("\n".join(kept))


def notes(text: str, version: str) -> str:
    """Return the notes of one version. Raise when it is missing or empty."""
    sections = parse(text)
    for section in sections:
        if section.version == version:
            check_section(section)
            result = notes_text(section.body)
            if not result:
                raise ChangelogError(f"v{version} has an empty section")
            return result
    raise ChangelogError(f"v{version} has no section in the changelog")


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    doc = __doc__ or ""
    parser = argparse.ArgumentParser(
        description=doc.split("\n", 1)[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=doc.split("\n", 1)[1],
    )
    parser.add_argument(
        "--changelog",
        type=Path,
        default=DEFAULT_CHANGELOG,
        help=f"Path to the changelog (default: {DEFAULT_CHANGELOG}).",
    )
    commands = parser.add_subparsers(dest="command", required=True)

    check_parser = commands.add_parser("check", help="Check the file.")
    check_parser.add_argument(
        "--require-unreleased",
        action="store_true",
        help="Also fail when ## Unreleased is empty.",
    )

    release_parser = commands.add_parser(
        "release", help="Rename ## Unreleased to a version."
    )
    release_parser.add_argument("--version", required=True, help="X.Y.Z")
    release_parser.add_argument("--build", required=True, type=int, help="N")
    release_parser.add_argument("--date", required=True, help="YYYY-MM-DD")

    notes_parser = commands.add_parser("notes", help="Write one version's notes.")
    notes_parser.add_argument("--version", required=True, help="X.Y.Z")
    notes_parser.add_argument(
        "--output", required=True, type=Path, help="The file to write."
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    path: Path = args.changelog
    try:
        text = path.read_text()
        if args.command == "check":
            sections = check(text, require_unreleased=args.require_unreleased)
            logger.info(
                "%s passes: ## %s and %d versions",
                path,
                UNRELEASED,
                len(sections) - 1,
            )
        elif args.command == "release":
            result = release(text, args.version, args.build, args.date)
            path.write_text(result)
            logger.info(
                "%s: ## %s is now v%s (build %d), %s",
                path,
                UNRELEASED,
                args.version,
                args.build,
                args.date,
            )
        else:
            result = notes(text, args.version)
            args.output.write_text(result)
            logger.info(
                "Wrote the notes for v%s to %s (%d characters)",
                args.version,
                args.output,
                len(result),
            )
    except (OSError, ChangelogError) as exc:
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
