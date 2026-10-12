"""Tests for scripts/bump_version.py."""

from __future__ import annotations

from pathlib import Path

import pytest

import bump_version
import check_version
from conftest import (
    ProjectWriter,
    build_configuration,
    consistent_project,
    project_text,
)


@pytest.mark.parametrize(
    ("part", "expected"),
    [("patch", "2.5.5"), ("minor", "2.6.0"), ("major", "3.0.0")],
)
def test_next_version_bumps_the_part(part: str, expected: str) -> None:
    assert bump_version.next_version("2.5.4", part) == expected


def test_next_version_starts_from_a_newer_tag() -> None:
    # A tag pushed by hand is ahead of the project: bump past the tag.
    assert bump_version.next_version("2.5.4", "patch", latest_tag="v2.5.9") == "2.5.10"


def test_next_version_ignores_an_older_tag() -> None:
    assert bump_version.next_version("2.5.4", "patch", latest_tag="v2.4.9") == "2.5.5"


def test_next_version_compares_numerically() -> None:
    assert bump_version.next_version("2.5.10", "patch", latest_tag="v2.5.9") == (
        "2.5.11"
    )


def test_next_version_rejects_an_unknown_part() -> None:
    with pytest.raises(ValueError, match="part"):
        bump_version.next_version("2.5.4", "build")


def test_next_version_rejects_a_malformed_tag() -> None:
    with pytest.raises(check_version.VersionError, match="tag"):
        bump_version.next_version("2.5.4", "patch", latest_tag="release-1")


def test_bump_replaces_every_entry() -> None:
    text, version = bump_version.bump(consistent_project("2.5.4", "56"), "minor")

    assert version == check_version.ProjectVersion(marketing="2.6.0", build=57)
    assert text.count("MARKETING_VERSION = 2.6.0;") == 4
    assert text.count("CURRENT_PROJECT_VERSION = 57;") == 4
    assert "2.5.4" not in text
    assert check_version.read_versions(text) == version


def test_bump_changes_nothing_else() -> None:
    before = consistent_project("2.5.4", "56")

    after, _ = bump_version.bump(before, "patch")

    restored = after.replace("2.5.5", "2.5.4").replace("= 57;", "= 56;")
    assert restored == before


def test_bump_refuses_entries_that_differ() -> None:
    # The old workflow bumped only entries equal to the first one, so a
    # differing entry stayed behind. Refuse instead.
    text = project_text(
        build_configuration("Debug", marketing="2.5.4"),
        build_configuration("Release", marketing="2.5.3"),
    )

    with pytest.raises(check_version.VersionError, match="differ"):
        bump_version.bump(text, "patch")


def test_main_writes_the_file_and_the_output(
    write_project: ProjectWriter, tmp_path: Path
) -> None:
    path = write_project(consistent_project("2.5.4", "56"))
    output = tmp_path / "github_output"

    status = bump_version.main(
        [
            "--project",
            str(path),
            "--part",
            "patch",
            "--latest-tag",
            "v2.5.4",
            "--github-output",
            str(output),
        ]
    )

    assert status == 0
    assert check_version.read_versions(path.read_text()) == (
        check_version.ProjectVersion(marketing="2.5.5", build=57)
    )
    assert output.read_text() == "version=2.5.5\nbuild=57\n"


def test_main_leaves_a_bad_project_untouched(write_project: ProjectWriter) -> None:
    before = project_text(
        build_configuration("Debug", build="56"),
        build_configuration("Release", build="55"),
    )
    path = write_project(before)

    assert bump_version.main(["--project", str(path), "--part", "patch"]) == 1
    assert path.read_text() == before


def test_main_accepts_an_empty_latest_tag(write_project: ProjectWriter) -> None:
    # A repo with no tag yet: the workflow passes an empty string.
    path = write_project(consistent_project("2.5.4", "56"))

    status = bump_version.main(
        ["--project", str(path), "--part", "patch", "--latest-tag", ""]
    )

    assert status == 0
    assert "MARKETING_VERSION = 2.5.5;" in path.read_text()
