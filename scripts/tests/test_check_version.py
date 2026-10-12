"""Tests for scripts/check_version.py.

The release job runs this check before it pushes a tag, so the negative cases
matter most: a check that passes a bad project ships the wrong version.
"""

from __future__ import annotations

from pathlib import Path

import pytest

import check_version
from conftest import (
    ProjectWriter,
    build_configuration,
    consistent_project,
    project_text,
)


def test_read_versions_returns_the_shared_version_and_build() -> None:
    version = check_version.read_versions(consistent_project("2.5.4", "56"))

    assert version == check_version.ProjectVersion(marketing="2.5.4", build=56)


def test_read_versions_reads_the_real_project() -> None:
    root = Path(__file__).resolve().parents[2]
    text = (root / check_version.DEFAULT_PROJECT).read_text()

    version = check_version.read_versions(text)

    assert version.marketing.count(".") == 2
    assert version.build > 0


def test_marketing_versions_that_differ_fail() -> None:
    text = project_text(
        build_configuration("Debug", marketing="2.5.4"),
        build_configuration("Release", marketing="2.5.3"),
    )

    with pytest.raises(check_version.VersionError, match=r"MARKETING_VERSION"):
        check_version.read_versions(text)


def test_build_numbers_that_differ_fail() -> None:
    text = project_text(
        build_configuration("Debug", build="56"),
        build_configuration("Release", build="55"),
    )

    with pytest.raises(check_version.VersionError, match=r"CURRENT_PROJECT_VERSION"):
        check_version.read_versions(text)


def test_a_configuration_with_no_marketing_version_fails() -> None:
    text = project_text(
        build_configuration("Debug"),
        build_configuration("Release", marketing=None),
    )

    with pytest.raises(check_version.VersionError, match=r"Release.*MARKETING"):
        check_version.read_versions(text)


def test_a_configuration_with_no_build_number_fails() -> None:
    text = project_text(
        build_configuration("Debug"),
        build_configuration("Release", build=None),
    )

    with pytest.raises(check_version.VersionError, match=r"Release.*CURRENT_PROJECT"):
        check_version.read_versions(text)


def test_a_project_with_no_version_entries_fails() -> None:
    text = project_text(build_configuration("Debug", marketing=None, build=None))

    with pytest.raises(check_version.VersionError, match=r"no MARKETING_VERSION"):
        check_version.read_versions(text)


@pytest.mark.parametrize("marketing", ["2.5", "2.5.4.1", "v2.5.4", "2.5.x", '""'])
def test_a_malformed_marketing_version_fails(marketing: str) -> None:
    text = project_text(build_configuration("Debug", marketing=marketing))

    with pytest.raises(check_version.VersionError, match=r"malformed"):
        check_version.read_versions(text)


@pytest.mark.parametrize("build", ["56.1", "abc", "-1", '""'])
def test_a_malformed_build_number_fails(build: str) -> None:
    text = project_text(build_configuration("Debug", build=build))

    with pytest.raises(check_version.VersionError, match=r"malformed"):
        check_version.read_versions(text)


def test_a_matching_tag_passes() -> None:
    version = check_version.ProjectVersion(marketing="2.5.4", build=56)

    check_version.check_tag("v2.5.4", version)


@pytest.mark.parametrize("tag", ["v2.5.3", "2.5.4", "v2.5.4.1", "v2.5.40", "V2.5.4"])
def test_a_tag_that_does_not_match_fails(tag: str) -> None:
    version = check_version.ProjectVersion(marketing="2.5.4", build=56)

    with pytest.raises(check_version.VersionError, match=r"tag"):
        check_version.check_tag(tag, version)


def test_main_passes_on_a_consistent_project(write_project: ProjectWriter) -> None:
    path = write_project(consistent_project())

    assert check_version.main(["--project", str(path), "--tag", "v2.5.4"]) == 0


def test_main_fails_on_a_mismatched_tag(write_project: ProjectWriter) -> None:
    path = write_project(consistent_project())

    assert check_version.main(["--project", str(path), "--tag", "v2.5.5"]) == 1


def test_main_fails_on_entries_that_differ(write_project: ProjectWriter) -> None:
    path = write_project(
        project_text(
            build_configuration("Debug", build="56"),
            build_configuration("Release", build="57"),
        )
    )

    assert check_version.main(["--project", str(path)]) == 1


def test_main_fails_on_a_missing_file(tmp_path: Path) -> None:
    assert check_version.main(["--project", str(tmp_path / "absent.pbxproj")]) == 1


def test_main_writes_github_output(
    write_project: ProjectWriter, tmp_path: Path
) -> None:
    path = write_project(consistent_project("2.5.4", "56"))
    output = tmp_path / "github_output"
    output.write_text("earlier=1\n")

    status = check_version.main(
        ["--project", str(path), "--github-output", str(output)]
    )

    assert status == 0
    assert output.read_text() == "earlier=1\nversion=2.5.4\nbuild=56\n"
