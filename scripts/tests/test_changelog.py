"""Tests for scripts/changelog.py.

The release job runs these checks before it pushes, and testers read the
notes. A check that passes a bad file ships wrong or empty notes, so the
refusals matter most.
"""

from __future__ import annotations

from pathlib import Path

import pytest

import changelog

HINT = '<!-- One "- " line per change, in plain words for testers. -->'

INTRO = "# Changelog\n\nRelease notes for testers.\n\n"

FOOTER = "---\n\nEarlier releases are on the GitHub releases page.\n"

SEEDED = (
    INTRO
    + "## Unreleased\n\n"
    + HINT
    + "\n\n"
    + "## v2.5.4 (build 56), 2026-10-12\n\n"
    + "- The CSV disclaimer no longer splits into columns.\n\n"
    + "## v2.5.3 (build 55), 2026-10-12\n\n"
    + "- Settings has a new close button.\n"
    + "- An export warns when Health access starts late.\n\n"
    + FOOTER
)


def with_unreleased(body: str, text: str = SEEDED) -> str:
    """Put `body` under ## Unreleased, after the hint."""
    return text.replace(HINT + "\n", HINT + "\n\n" + body + "\n", 1)


@pytest.fixture
def changelog_file(tmp_path: Path) -> Path:
    path = tmp_path / "changelog.md"
    path.write_text(SEEDED)
    return path


def test_the_hint_is_the_one_release_writes() -> None:
    assert changelog.UNRELEASED_HINT == HINT


# --- check: a valid file -------------------------------------------------


def test_check_passes_on_a_valid_file() -> None:
    changelog.check(SEEDED)


def test_check_passes_with_no_version_sections() -> None:
    changelog.check(INTRO + "## Unreleased\n")


def test_check_require_unreleased_passes_with_a_line() -> None:
    changelog.check(with_unreleased("- A new thing."), require_unreleased=True)


def test_check_reads_the_repo_changelog() -> None:
    root = Path(__file__).resolve().parents[2]

    changelog.check((root / changelog.DEFAULT_CHANGELOG).read_text())


# --- check: structure refusals -------------------------------------------


def test_a_file_that_does_not_start_with_the_title_fails() -> None:
    with pytest.raises(changelog.ChangelogError, match=r"# Changelog"):
        changelog.check(SEEDED.replace("# Changelog", "# Release notes", 1))


def test_a_missing_unreleased_section_fails() -> None:
    text = SEEDED.replace("## Unreleased\n\n" + HINT + "\n\n", "", 1)

    with pytest.raises(changelog.ChangelogError, match=r"Unreleased"):
        changelog.check(text)


def test_two_unreleased_sections_fail() -> None:
    text = SEEDED.replace("## v2.5.3", "## Unreleased\n\n- Again.\n\n## v2.5.3", 1)

    with pytest.raises(changelog.ChangelogError, match=r"Unreleased.*once"):
        changelog.check(text)


def test_unreleased_after_a_version_fails() -> None:
    text = (
        INTRO
        + "## v2.5.4 (build 56), 2026-10-12\n\n- One.\n\n"
        + "## Unreleased\n\n- Two.\n"
    )

    with pytest.raises(changelog.ChangelogError, match=r"first"):
        changelog.check(text)


@pytest.mark.parametrize(
    "heading",
    [
        "## 2.5.2 (build 54), 2026-10-12",
        "## v2.5.2",
        "## v2.5.2 (build 54)",
        "## v2.5.2 (build 54) 2026-10-12",
        "## v2.5 (build 54), 2026-10-12",
        "## v2.5.2 (build x), 2026-10-12",
        "## v2.5.2 (build 54), 2026-13-01",
        "## v2.5.2 (build 54), 12-10-2026",
        "## Released",
        "## unreleased",
        "##",
    ],
)
def test_a_malformed_heading_fails(heading: str) -> None:
    text = SEEDED.replace(FOOTER, heading + "\n\n- Old.\n\n" + FOOTER, 1)

    with pytest.raises(changelog.ChangelogError, match=r"heading"):
        changelog.check(text)


def test_a_duplicate_version_fails() -> None:
    text = SEEDED.replace(
        FOOTER, "## v2.5.3 (build 54), 2026-10-12\n\n- Again.\n\n" + FOOTER, 1
    )

    with pytest.raises(changelog.ChangelogError, match=r"v2\.5\.3.*twice"):
        changelog.check(text)


def test_versions_out_of_order_fail() -> None:
    text = SEEDED.replace(
        FOOTER, "## v2.5.10 (build 60), 2026-10-12\n\n- Newer.\n\n" + FOOTER, 1
    )

    with pytest.raises(changelog.ChangelogError, match=r"order"):
        changelog.check(text)


def test_a_heading_after_the_footer_fails() -> None:
    text = SEEDED + "\n## v2.5.2 (build 54), 2026-10-12\n\n- Old.\n"

    with pytest.raises(changelog.ChangelogError, match=r"footer"):
        changelog.check(text)


def test_an_unclosed_comment_fails() -> None:
    text = with_unreleased("<!-- no end")

    with pytest.raises(changelog.ChangelogError, match=r"comment"):
        changelog.check(text)


def test_a_heading_inside_a_comment_is_ignored() -> None:
    text = with_unreleased("<!--\n## Not a heading\n-->\n- Real line.")

    changelog.check(text, require_unreleased=True)


# --- check: content refusals ---------------------------------------------


def test_an_empty_unreleased_fails_with_require_unreleased() -> None:
    text = SEEDED.replace(HINT, "", 1)

    with pytest.raises(changelog.ChangelogError, match=r"Unreleased.*empty"):
        changelog.check(text, require_unreleased=True)


def test_a_comment_only_unreleased_fails_with_require_unreleased() -> None:
    with pytest.raises(changelog.ChangelogError, match=r"Unreleased.*empty"):
        changelog.check(SEEDED, require_unreleased=True)


def test_an_empty_unreleased_passes_without_require_unreleased() -> None:
    changelog.check(SEEDED)


# The notes file ends with a newline, and TestFlight counts it.
def test_a_section_at_the_limit_passes() -> None:
    body = "- " + "a" * (changelog.MAX_NOTES_LENGTH - 3)

    changelog.check(with_unreleased(body))


def test_a_section_that_is_too_long_fails() -> None:
    body = "- " + "a" * (changelog.MAX_NOTES_LENGTH - 2)

    with pytest.raises(changelog.ChangelogError, match=r"4001.*4000"):
        changelog.check(with_unreleased(body))


def test_comments_do_not_count_toward_the_limit() -> None:
    body = "<!-- " + "a" * 5000 + " -->\n- Short."

    changelog.check(with_unreleased(body))


@pytest.mark.parametrize(
    "line",
    [
        "- Run `make` first.",
        "- This is **bold**.",
        "- See [the docs](https://example.com).",
    ],
)
def test_markdown_formatting_in_notes_fails(line: str) -> None:
    with pytest.raises(changelog.ChangelogError, match=r"plain"):
        changelog.check(with_unreleased(line))


def test_markdown_formatting_in_a_comment_passes() -> None:
    changelog.check(with_unreleased("<!-- `code` and **bold** -->\n- Plain."))


# --- release ---------------------------------------------------------------


def test_release_renames_unreleased_and_adds_an_empty_one() -> None:
    text = with_unreleased("- First change.\n- Second change.")

    result = changelog.release(text, "2.5.5", 57, "2026-10-13")

    assert result == (
        INTRO
        + "## Unreleased\n\n"
        + HINT
        + "\n\n"
        + "## v2.5.5 (build 57), 2026-10-13\n\n"
        + "- First change.\n- Second change.\n\n"
        + "## v2.5.4 (build 56), 2026-10-12\n\n"
        + "- The CSV disclaimer no longer splits into columns.\n\n"
        + "## v2.5.3 (build 55), 2026-10-12\n\n"
        + "- Settings has a new close button.\n"
        + "- An export warns when Health access starts late.\n\n"
        + FOOTER
    )
    changelog.check(result)


def test_release_into_a_file_with_no_versions() -> None:
    text = INTRO + "## Unreleased\n\n- First.\n"

    result = changelog.release(text, "1.0.0", 1, "2026-10-13")

    assert result == (
        INTRO
        + "## Unreleased\n\n"
        + HINT
        + "\n\n## v1.0.0 (build 1), 2026-10-13\n\n- First.\n"
    )


def test_release_refuses_an_empty_unreleased() -> None:
    with pytest.raises(changelog.ChangelogError, match=r"Unreleased.*empty"):
        changelog.release(SEEDED, "2.5.5", 57, "2026-10-13")


def test_release_refuses_an_existing_version() -> None:
    text = with_unreleased("- A change.")

    with pytest.raises(changelog.ChangelogError, match=r"v2\.5\.4.*already"):
        changelog.release(text, "2.5.4", 57, "2026-10-13")


def test_release_refuses_a_version_older_than_the_newest() -> None:
    text = with_unreleased("- A change.")

    with pytest.raises(changelog.ChangelogError, match=r"order"):
        changelog.release(text, "2.5.0", 57, "2026-10-13")


@pytest.mark.parametrize(
    ("version", "build", "date"),
    [
        ("v2.5.5", 57, "2026-10-13"),
        ("2.5", 57, "2026-10-13"),
        ("2.5.5", 0, "2026-10-13"),
        ("2.5.5", 57, "2026-10-32"),
        ("2.5.5", 57, "13-10-2026"),
    ],
)
def test_release_refuses_malformed_arguments(
    version: str, build: int, date: str
) -> None:
    with pytest.raises(changelog.ChangelogError):
        changelog.release(with_unreleased("- A change."), version, build, date)


def test_release_refuses_a_broken_file() -> None:
    text = with_unreleased("- A change.").replace("## v2.5.3", "## v2.5.30", 1)

    with pytest.raises(changelog.ChangelogError):
        changelog.release(text, "2.5.31", 57, "2026-10-13")


# --- notes -----------------------------------------------------------------


def test_notes_strip_comments_and_trim_blank_lines() -> None:
    text = SEEDED.replace(
        "- Settings has a new close button.\n",
        "\n<!-- hidden -->\n\n- Settings has a new close button.  \n"
        "<!-- inline --> \n\n\n",
        1,
    )

    assert changelog.notes(text, "2.5.3") == (
        "- Settings has a new close button.\n\n"
        "- An export warns when Health access starts late.\n"
    )


def test_notes_for_the_last_section_exclude_the_footer() -> None:
    assert changelog.notes(SEEDED, "2.5.3") == (
        "- Settings has a new close button.\n"
        "- An export warns when Health access starts late.\n"
    )


def test_notes_refuse_a_missing_version() -> None:
    with pytest.raises(changelog.ChangelogError, match=r"v2\.4\.0.*no section"):
        changelog.notes(SEEDED, "2.4.0")


def test_notes_refuse_an_empty_section() -> None:
    text = SEEDED.replace(
        "- The CSV disclaimer no longer splits into columns.\n", "<!-- x -->\n", 1
    )

    with pytest.raises(changelog.ChangelogError, match=r"v2\.5\.4.*empty"):
        changelog.notes(text, "2.5.4")


def test_notes_refuse_a_broken_file() -> None:
    text = SEEDED.replace("## Unreleased", "## Next", 1)

    with pytest.raises(changelog.ChangelogError):
        changelog.notes(text, "2.5.4")


def test_release_then_notes_round_trip() -> None:
    text = with_unreleased("- Exports finish faster.\n<!-- for #200 -->\n- New tile.")

    released = changelog.release(text, "2.5.5", 57, "2026-10-13")

    # The hint moves to the new Unreleased; other comments stay with the release.
    assert released.count(HINT) == 1
    assert (
        "## v2.5.5 (build 57), 2026-10-13\n\n"
        "- Exports finish faster.\n<!-- for #200 -->\n- New tile.\n\n"
    ) in released

    assert changelog.notes(released, "2.5.5") == (
        "- Exports finish faster.\n- New tile.\n"
    )
    changelog.check(released)
    with pytest.raises(changelog.ChangelogError, match=r"Unreleased.*empty"):
        changelog.check(released, require_unreleased=True)


# --- main ------------------------------------------------------------------


def test_main_check_passes(changelog_file: Path) -> None:
    assert changelog.main(["--changelog", str(changelog_file), "check"]) == 0


def test_main_check_require_unreleased_fails_on_an_empty_section(
    changelog_file: Path,
) -> None:
    status = changelog.main(
        ["--changelog", str(changelog_file), "check", "--require-unreleased"]
    )

    assert status == 1


def test_main_fails_on_a_missing_file(tmp_path: Path) -> None:
    status = changelog.main(["--changelog", str(tmp_path / "absent.md"), "check"])

    assert status == 1


def test_main_release_rewrites_the_file(changelog_file: Path) -> None:
    changelog_file.write_text(with_unreleased("- A change."))

    status = changelog.main(
        [
            "--changelog",
            str(changelog_file),
            "release",
            "--version",
            "2.5.5",
            "--build",
            "57",
            "--date",
            "2026-10-13",
        ]
    )

    assert status == 0
    text = changelog_file.read_text()
    assert "## v2.5.5 (build 57), 2026-10-13\n\n- A change.\n" in text
    assert changelog.notes(text, "2.5.5") == "- A change.\n"


def test_main_release_leaves_the_file_unchanged_on_a_refusal(
    changelog_file: Path,
) -> None:
    status = changelog.main(
        [
            "--changelog",
            str(changelog_file),
            "release",
            "--version",
            "2.5.5",
            "--build",
            "57",
            "--date",
            "2026-10-13",
        ]
    )

    assert status == 1
    assert changelog_file.read_text() == SEEDED


def test_main_notes_writes_the_output(changelog_file: Path, tmp_path: Path) -> None:
    output = tmp_path / "notes.md"

    status = changelog.main(
        [
            "--changelog",
            str(changelog_file),
            "notes",
            "--version",
            "2.5.4",
            "--output",
            str(output),
        ]
    )

    assert status == 0
    assert output.read_text() == (
        "- The CSV disclaimer no longer splits into columns.\n"
    )


def test_main_notes_fails_on_a_missing_version_and_writes_nothing(
    changelog_file: Path, tmp_path: Path
) -> None:
    output = tmp_path / "notes.md"

    status = changelog.main(
        [
            "--changelog",
            str(changelog_file),
            "notes",
            "--version",
            "2.4.0",
            "--output",
            str(output),
        ]
    )

    assert status == 1
    assert not output.exists()


def test_an_inline_comment_keeps_the_text_after_it() -> None:
    text = with_unreleased("<!-- a --> Kept.\n<!-- b -->\n- Next.")

    assert changelog.notes(
        changelog.release(text, "2.5.5", 57, "2026-10-13"), "2.5.5"
    ) == (" Kept.\n- Next.\n")
