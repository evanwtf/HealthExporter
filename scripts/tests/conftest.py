"""Fixtures for the release script tests."""

from __future__ import annotations

from collections.abc import Callable
from pathlib import Path

import pytest

ProjectWriter = Callable[[str], Path]


def build_configuration(
    name: str,
    *,
    marketing: str | None = "2.5.4",
    build: str | None = "56",
) -> str:
    """One XCBuildConfiguration block, as Xcode writes it in project.pbxproj.

    Pass None to leave a key out of the block.
    """
    lines = [
        f"\t\t1DBDF7582F10AFD8008549F{len(name)} /* {name} */ = {{",
        "\t\t\tisa = XCBuildConfiguration;",
        "\t\t\tbuildSettings = {",
        "\t\t\t\tCODE_SIGN_STYLE = Automatic;",
    ]
    if build is not None:
        lines.append(f"\t\t\t\tCURRENT_PROJECT_VERSION = {build};")
    lines += [
        "\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (",
        '\t\t\t\t\t"$(inherited)",',
        "\t\t\t\t);",
    ]
    if marketing is not None:
        lines.append(f"\t\t\t\tMARKETING_VERSION = {marketing};")
    lines += [
        "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.evanhoffman.HealthExporter;",
        "\t\t\t};",
        f"\t\t\tname = {name};",
        "\t\t};",
    ]
    return "\n".join(lines) + "\n"


def project_text(*configurations: str) -> str:
    """A project.pbxproj body with a project-level configuration and the
    given target configurations. The project-level block has no version keys,
    as in the real file."""
    project_level = build_configuration("ProjectDebug", marketing=None, build=None)
    return (
        "// !$*UTF8*$!\n{\n\tobjects = {\n"
        "/* Begin XCBuildConfiguration section */\n"
        + project_level
        + "".join(configurations)
        + "/* End XCBuildConfiguration section */\n\t};\n}\n"
    )


def consistent_project(marketing: str = "2.5.4", build: str = "56") -> str:
    """Four target configurations that agree, like the real project."""
    return project_text(
        *(
            build_configuration(name, marketing=marketing, build=build)
            for name in ("Debug", "Release", "TestsDebug", "TestsRelease")
        )
    )


@pytest.fixture
def write_project(tmp_path: Path) -> ProjectWriter:
    def write(text: str) -> Path:
        path = tmp_path / "project.pbxproj"
        path.write_text(text)
        return path

    return write
